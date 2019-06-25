/*
 Copyright (c) 2015, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3.  Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ORKHeartRateVideoProcessor.h"
#import "ORKHeartRateRecorder.h"
#import "ORKRecorder_Internal.h"
#import "ORKHelpers_Internal.h"
#import <ResearchKit/ResearchKit-Swift.h>


@interface ORKHeartRateRecorder ()

//@property (nonatomic, strong) AVAudioRecorder *audioRecorder;

@property (nonatomic, strong) AVCaptureSession *videoSession;

@property (nonatomic, strong) AVCaptureDevice *captureDevice;

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@property (nonatomic, strong) NSMutableArray<CRFPixelSample *> *loggingSamples;

@property (nonatomic, strong) ORKHeartRateVideoProcessor *videoProcessor;

@property (nonatomic, copy) NSDictionary *recorderSettings;

@property (nonatomic, copy) CRFHeartRateSampleProcessor *sampleProcessor;

@end

@implementation ORKHeartRateRecorder

int flashRetryCount = 0;

const int MAX_RETRIES = 10;

double flashTime;

- (void)dealloc {
    ORK_Log_Debug(@"Remove heartraterecorder %p", self);

    _videoProcessor = nil;
}

+ (NSDictionary *)defaultRecorderSettings {
    return @{};
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                  recorderSettings:(NSDictionary *)recorderSettings
                              step:(ORKStep *)step
                   outputDirectory:(NSURL *)outputDirectory {
    self = [super initWithIdentifier:identifier step:step outputDirectory:outputDirectory];
    if (self) {
        
        self.continuesInBackground = YES;

        if (!recorderSettings) {
            recorderSettings = [[self class] defaultRecorderSettings];
        }

        _sampleProcessor = [[CRFHeartRateSampleProcessor alloc] init];

        if (![recorderSettings isKindOfClass:[NSDictionary class]]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"recorderSettings should be a dictionary" userInfo:recorderSettings];
        }

        self.recorderSettings = recorderSettings;
    }
    return self;
}

- (AVCaptureDevice *) getCaptureDevice {

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInTelephotoCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];

    return device;
}

- (void)start {

    if (self.outputDirectory == nil) {
        @throw [NSException exceptionWithName:NSDestinationInvalidException reason:@"heartRateRecorder requires an output directory" userInfo:nil];
    }

    //NSLog(@"_crfDelegate %@",_crfDelegate);

    [_sampleProcessor reset];

    __weak typeof(self) weakSelf = self;
    _sampleProcessor.callback = ^(double bpm, double confidence) {
         //NSLog(@"_sampleProcessor.callback %f %f\n",bpm,confidence);
        _bpm = bpm;
        _confidence = confidence;
        [weakSelf.crfDelegate updateBPM:bpm];
    };

    if (_videoSession) {
        NSLog(@"ERROR: Already had session\n");
        return;
    }

    _videoSession = [[AVCaptureSession alloc] init];
    _videoSession.sessionPreset = AVCaptureSessionPresetLow;

    // Only create the file when we should actually start recording.
    if (!_captureDevice) {

        NSError __autoreleasing *error = nil;
        //NSURL *videoFileURL = [self recordingFileURL];

        if (![self recreateFileWithError:&error]) {
            [self finishRecordingWithError:error];
            return;
        }

        ORK_Log_Debug(@"Create videoRecorder %p", self);

        _captureDevice = [self getCaptureDevice];

        if (!_captureDevice) {
            NSLog(@"ERROR: noBackCamera\n");
            // throw CRFHeartRateRecorderError.noBackCamera
            return;
        }

        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&error];

        if (error) { // should throw?
            NSLog(@"ERROR: AVCaptureDeviceInput\n");
            return;
        }

        [_videoSession addInput:input];

        // configuration

        AVCaptureDeviceFormat *currentFormat;

        for (AVCaptureDeviceFormat *format in _captureDevice.formats) {
            AVFrameRateRange *frameRateRange = format.videoSupportedFrameRateRanges.firstObject;
            if (!frameRateRange || frameRateRange.maxFrameRate != 60) {
                //NSLog(@"ERROR: frameRateRange %@ %f\n",frameRateRange,frameRateRange.maxFrameRate);
                continue;
            }

            if (!currentFormat) {
                currentFormat = format;
                continue;
            }

            CMVideoDimensions currentSize = CMVideoFormatDescriptionGetDimensions(currentFormat.formatDescription);
            CMVideoDimensions formatSize = CMVideoFormatDescriptionGetDimensions(format.formatDescription);

            //NSLog(@"CMVideoFormatDescriptionGetDimensions %d %d %d %d\n", currentSize.width, currentSize.height, formatSize.width, formatSize.height);
            if (formatSize.width < currentSize.width && formatSize.height < currentSize.height) {
                currentFormat = format;
            }
        }
        NSLog(@"currentFormat %@\n", currentFormat);
        int frameRate = 60;

        
        /*
         if !CRFSupportedFrameRates.contains(frameRate) {
         // Allow the camera settings to set the framerate to a value that is not supported to allow for
         // customization of the camera settings.
         debugPrint("WARNING!! \(frameRate) is NOT a supported framerate for calculating BPM.")
         }*/


        dispatch_queue_t processingQueue = dispatch_queue_create("io.carechain.heartrate.processing", DISPATCH_QUEUE_SERIAL);

        _videoProcessor = [[ORKHeartRateVideoProcessor alloc] initWithDelegate:self frameRate:frameRate callbackQueue:processingQueue];

        {

            [_captureDevice lockForConfiguration:&error];
            if (!error) {
                _captureDevice.activeFormat = currentFormat;


                _captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, _videoProcessor.frameRate);
                _captureDevice.activeVideoMaxFrameDuration = CMTimeMake(1, _videoProcessor.frameRate);

                if (currentFormat.isVideoHDRSupported) {
                    [_captureDevice setVideoHDREnabled:false];
                    _captureDevice.automaticallyAdjustsVideoHDREnabled = false;
                }

                if (_captureDevice.isLockingFocusWithCustomLensPositionSupported) {
                    [_captureDevice setFocusModeLockedWithLensPosition:1.0 completionHandler:nil];
                } else if (_captureDevice.isAutoFocusRangeRestrictionSupported) {
                    // FIXME  captureDevice.autoFocusRangeRestriction = (cameraSettings.focusLensPosition >= 0.5) ? .far : .near
                    _captureDevice.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionFar;

                    if (_captureDevice.isFocusPointOfInterestSupported) {
                        _captureDevice.focusPointOfInterest = CGPointMake(0.5, 0.5);
                    }
                }

                if ([_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom]) {
                    // default duration 1.0 / 120.0
                    CMTime duration = CMTimeMakeWithSeconds(1.0 / 120.0, 1000);
                    float iso = MIN(MAX(60, currentFormat.minISO), currentFormat.maxISO);
                    [_captureDevice setExposureModeCustomWithDuration:duration ISO:iso completionHandler:nil];

                }

                if ([_captureDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {

                    AVCaptureWhiteBalanceTemperatureAndTintValues wb;
                    wb.temperature = 5200;
                    wb.tint = 0;

                    AVCaptureWhiteBalanceGains gains = [_captureDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:wb];
                    [_captureDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:nil];
                }

                [_captureDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:&error];

                [_captureDevice unlockForConfiguration];
            }

            AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];

            dispatch_queue_t captureQueue = dispatch_queue_create("io.carechain.heartrate.capture", DISPATCH_QUEUE_SERIAL);

            [videoOutput setSampleBufferDelegate:self queue:captureQueue];

            //NSNumber *formatType = videoOutput.availableVideoCVPixelFormatTypes.firstObject;

            videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]};

            //NSLog(@"formatType %@",formatType);
            // @(kCVPixelFormatType_32ARGB)
            videoOutput.alwaysDiscardsLateVideoFrames = false;

            if (_crfDelegate ) {

                UIView *view = [_crfDelegate previewView];
                if (view) {
                    AVCaptureVideoPreviewLayer *videoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_videoSession];
                    videoPreviewLayer.frame = view.layer.frame;
                    _videoPreviewLayer = videoPreviewLayer;
                    [view.layer addSublayer:videoPreviewLayer];
                }
            }

            [_videoSession addOutput:videoOutput];
            [_videoSession startRunning];
        }
    }

    [super start];

    if (_crfDelegate) {
        [_crfDelegate didFinishStartingCamera];
    }
    
}

- (void)stop {

    /*
    if (!_audioRecorder) {
        // Error has already been returned.
        return;
    }*/
    
    [self doStopRecording];
    
    NSURL *fileUrl = [self recordingFileURL];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[[self recordingFileURL] path]]) {
        fileUrl = nil;
    }
    
    [self reportFileResultWithFile:fileUrl error:nil];
    
    [super stop];
}

- (BOOL)isRecording {
    return [_videoSession isRunning];
}

- (NSString *)mimeType {
    return @"video/mp4";
}

- (NSString *)recorderType {
    return @"video";
}

- (void)doStopRecording {

    if (self.isRecording) {

#if !TARGET_IPHONE_SIMULATOR
        if (_captureDevice) {
            [self turnOffTorch:_captureDevice];
        }

        if (_videoPreviewLayer) {
            [_videoPreviewLayer removeFromSuperlayer];
            _videoPreviewLayer = nil;
        }

        [_videoSession stopRunning];
        _videoSession = nil;
        [self applyFileProtection:ORKFileProtectionComplete toFileAtURL:[self recordingFileURL]];
#endif
     }
}

-(void) turnOnTorch:(AVCaptureDevice *) captureDevice  {

    dispatch_async(dispatch_get_main_queue(), ^{
        NSError __autoreleasing *error = nil;
        [_captureDevice lockForConfiguration:&error];
        if (!error) {
            [_captureDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:&error];
            [_captureDevice unlockForConfiguration];
        }
        if (error) {
            NSLog(@"error %@\n",error.localizedDescription);
        }
    });
}


-(void) turnOffTorch:(AVCaptureDevice *) captureDevice  {

    dispatch_async(dispatch_get_main_queue(), ^{
        NSError __autoreleasing *error = nil;
        [_captureDevice lockForConfiguration:&error];
        if (!error) {
            _captureDevice.torchMode = AVCaptureTorchModeAuto;
            [_captureDevice unlockForConfiguration];
        }
        if (error) {
            NSLog(@"error %@\n",error.localizedDescription);
        }
    });
}

- (void)finishRecordingWithError:(NSError *)error {
    [self doStopRecording];
    [super finishRecordingWithError:error];
}

- (NSString *)extension {
    NSString *extension = @"m4a";
    return extension;
}

- (NSURL *)recordingFileURL {
    return [[self recordingDirectoryURL] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [self logName], [self extension]]];
}

- (BOOL)recreateFileWithError:(NSError **)errorOut {
    NSURL *url = [self recordingFileURL];

    if (!url) {
        if (errorOut != NULL) {
            *errorOut = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:@{NSLocalizedDescriptionKey:ORKLocalizedString(@"ERROR_RECORDER_NO_OUTPUT_DIRECTORY", nil)}];
        }
        return NO;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:errorOut]) {
        return NO;
    }
    
    if ([fileManager fileExistsAtPath:[url path]]) {
        if (![fileManager removeItemAtPath:[url path] error:errorOut]) {
            return NO;
        }
    }
    
    [fileManager createFileAtPath:[url path] contents:nil attributes:nil];
    [fileManager setAttributes:@{NSFileProtectionKey: ORKFileProtectionFromMode(ORKFileProtectionCompleteUnlessOpen)} ofItemAtPath:[url path] error:errorOut];
    return YES;
}

- (void)reset {
    _captureDevice = nil;
    [super reset];
}

-(CRFHeartRateBPMSample *)restingHeartRate {
    return [_sampleProcessor restingHeartRate];
}

-(CRFHeartRateBPMSample *)peakHeartRate {
    return [_sampleProcessor peakHeartRate];
}

-(CRFHeartRateBPMSample *)endHeartRate {
    return [_sampleProcessor endHeartRate];
}

-(double)hrvSDNN {
    NSNumber *number = [_sampleProcessor hrvSDNN];
    return number.doubleValue;
}

//public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    flashRetryCount = 0;
    while (_captureDevice && _captureDevice.torchMode != AVCaptureTorchModeOn && flashRetryCount < MAX_RETRIES) {
        [self turnOnTorch:_captureDevice];
        flashRetryCount++;
    }

    [_videoProcessor appendVideoSampleBuffer:sampleBuffer];
}


- (void)processor:(ORKHeartRateVideoProcessor *)processor didCaptureSample:(CRFPixelSample *)sample {
    [self recordColor:sample];
}

- (void) recordColor:(CRFPixelSample *) sample {

    BOOL coveringLens = sample.isCoveringLens;
    if (coveringLens != self.isCoveringLens) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isCoveringLens = coveringLens;
            /*
            if let previewLayer = self._videoPreviewLayer {
                if coveringLens {
                    previewLayer.removeFromSuperlayer()
                } else {
                    self.crfDelegate?.previewView?.layer.addSublayer(previewLayer)
                }
            }*/
        });
    }

    [_sampleProcessor processSample:sample];

    if (_crfDelegate) {
        [_crfDelegate updateSample:sample];
    }

    [_loggingSamples addObject:sample];
    

    if (_loggingSamples.count >= _videoProcessor.frameRate) {

        NSArray<CRFPixelSample *> *samples = [_loggingSamples sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {

            CRFPixelSample *first  = (CRFPixelSample *)obj1;
            CRFPixelSample *second = (CRFPixelSample *)obj2;

            return first.presentationTimestamp < second.presentationTimestamp;
        }];
        [_loggingSamples removeAllObjects];
        [self writeSamples:samples];
    }
}

-(void) writeSamples:(NSArray<CRFPixelSample *> *) samples {

    for (CRFPixelSample* sample in samples) {
        NSLog(@"CRFPixelSample %@\n",sample);
    }
}

@end


@implementation ORKHeartRateRecorderConfiguration

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype)initWithIdentifier:(NSString *)identifier {
    @throw [NSException exceptionWithName:NSGenericException reason:@"Use subclass designated initializer" userInfo:nil];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                  recorderSettings:(NSDictionary *)recorderSettings {
    self = [super initWithIdentifier:identifier];
    if (self) {
        if (recorderSettings && ![recorderSettings isKindOfClass:[NSDictionary class]]) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"recorderSettings should be a dictionary" userInfo:recorderSettings];
        }
        _recorderSettings = recorderSettings;
    }
    return self;
}
#pragma clang diagnostic pop

- (ORKRecorder *)recorderForStep:(ORKStep *)step
                 outputDirectory:(NSURL *)outputDirectory {


    return [[ORKHeartRateRecorder alloc] initWithIdentifier:self.identifier
                                       recorderSettings:self.recorderSettings
                                                   step:step
                                        outputDirectory:outputDirectory];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        ORK_DECODE_OBJ_CLASS(aDecoder, recorderSettings, NSDictionary);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    ORK_ENCODE_OBJ(aCoder, recorderSettings);
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)object {
    BOOL isParentSame = [super isEqual:object];
    
    __typeof(self) castObject = object;
    return (isParentSame &&
            ORKEqualObjects(self.recorderSettings, castObject.recorderSettings));
}

- (ORKPermissionMask)requestedPermissionMask {
    return ORKPermissionCamera;
}

@end
