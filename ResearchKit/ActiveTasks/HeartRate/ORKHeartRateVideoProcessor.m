//
//  ORKHeartRateVideoProcessor.m
//  CardiorespiratoryFitness
//
//  Copyright © 2017-2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "ORKHeartRateVideoProcessor.h"

typedef NS_ENUM(NSInteger, MovieRecorderStatus) {
    MovieRecorderStatusIdle = 0,
    MovieRecorderStatusPreparingToRecord,
    MovieRecorderStatusRecording,
    MovieRecorderStatusFinishingRecordingPart1, // waiting for inflight buffers to be appended
    MovieRecorderStatusFinishingRecordingPart2, // calling finish writing on the asset writer
    MovieRecorderStatusFinished,    // terminal state
    MovieRecorderStatusFailed        // terminal state
}; // internal state machine

const int CRFHeartRateResolutionWidth = 192;    // lowest resolution on an iPhone 6
const int CRFHeartRateResolutionHeight = 144;   // lowest resolution on an iPhone 6
const long CRFRedStdDevThreshold = 15.0;

@implementation ORKHeartRateVideoProcessor {
    dispatch_queue_t _processingQueue;
    
    MovieRecorderStatus _status;
    AVAssetWriter *_assetWriter;
    BOOL _haveStartedSession;
    AVAssetWriterInput *_videoInput;
    
    __weak id<ORKHeartRateVideoProcessorDelegate> _delegate;
    dispatch_queue_t _delegateCallbackQueue;
}

- (instancetype)initWithDelegate:(id<ORKHeartRateVideoProcessorDelegate>)delegate frameRate:(int)frameRate callbackQueue:(dispatch_queue_t)queue {
    NSParameterAssert(delegate != nil);
    NSParameterAssert(queue != nil);
    
    self = [super init];
    if (self) {
        _delegate = delegate;
        _delegateCallbackQueue = queue;
        _processingQueue = dispatch_queue_create("io.carechain.heartRateSample.processing", DISPATCH_QUEUE_SERIAL);
        _frameRate = frameRate;
        _startSystemUptime = [[NSProcessInfo processInfo] systemUptime];
    }
    return self;
}

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {

    if (sampleBuffer == NULL) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"NULL sample buffer" userInfo:nil];
        return;
    }
    
    CFRetain(sampleBuffer);
    dispatch_async(_processingQueue, ^{
        @autoreleasepool {
            
            // Process the sample
            BOOL isLensCovered = [self processSampleBuffer:sampleBuffer];
            
            // Now, look to see if this sample should be saved to video
            @synchronized(self) {
                // From the client's perspective the movie recorder can asynchronously transition to an error state as
                // the result of an append. Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if (!isLensCovered || (self->_status != MovieRecorderStatusRecording)) {
                    CFRelease(sampleBuffer);
                    return;
                }
            }

            if (self->_videoInput.readyForMoreMediaData) {
                BOOL success = [self->_videoInput appendSampleBuffer:sampleBuffer];
                if (!success) {
                    NSError *error = self->_assetWriter.error;
                    NSLog( @"video input failed to append buffer sample. %@", error);
                    @synchronized(self) {
                        [self transitionToStatus:MovieRecorderStatusFailed error:error];
                    }
                }
            } else {
                NSLog( @"video input not ready for more media data, dropping buffer");
            }
            CFRelease(sampleBuffer);
        }
    });
}

- (BOOL)processSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef cvimgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    return [self processImageBuffer:cvimgRef timestamp:pts];
}

- (BOOL)processImageBuffer:(CVImageBufferRef)cvimgRef timestamp:(CMTime)pts {
    
    // Lock the image buffer
    CVPixelBufferLockBaseAddress(cvimgRef,0);
    
    // access the data
    uint64_t width = CVPixelBufferGetWidth(cvimgRef);
    uint64_t height = CVPixelBufferGetHeight(cvimgRef);
    
    // get the raw image bytes
    uint8_t *buf=(uint8_t *) CVPixelBufferGetBaseAddress(cvimgRef);
    size_t bprow=CVPixelBufferGetBytesPerRow(cvimgRef);

    // Calculate average
    double r = 0, g = 0, b = 0;
    
    long widthScaleFactor = 1;
    long heightScaleFactor = 1;
    if ((width > CRFHeartRateResolutionWidth) && (height > CRFHeartRateResolutionHeight)) {
        // Downsample the resolution to approximately 192x144 (with round number scaling).
        widthScaleFactor = floor((double)width / (double)CRFHeartRateResolutionWidth);
        heightScaleFactor = floor((double)height / (double)CRFHeartRateResolutionHeight);
    }
    long size = (width/widthScaleFactor + widthScaleFactor) * (height/heightScaleFactor + heightScaleFactor);
    
    double rValues[size];
    long count = 0;
    
    // Get the average rgb values for the entire image.
    for (int y = 0; y < height; y += heightScaleFactor) {
        for (int x = 0; x < width * 4; x += (4 * widthScaleFactor)) {
            double red = buf[x + 2];
            double green = buf[x + 1];
            double blue = buf[x];
            
            rValues[count] = (double)red;
            count++;
            
            r += red;
            g += green;
            b += blue;
        }
        buf += bprow;
    }

    r /= (double)count;
    g /= (double)count;
    b /= (double)count;

    double redMean = r/255.0;

    double rDiffSum = 0;
    //double rSum = 0;
    for (long ii = 0; ii < count; ii++) {
        double rDiff = rValues[ii] - r;
        rDiffSum += (rDiff * rDiff);
        //rSum += rValues[ii];
    }

    double redSD = sqrt(rDiffSum / (double)(count - 1));
    BOOL isCoveringLens = (redSD <= CRFRedStdDevThreshold);
    
    // Unlock the image buffer
    CVPixelBufferUnlockBaseAddress(cvimgRef,0);
    
    // Create a struct to return the pixel average
    CRFPixelSample *sample = [[CRFPixelSample alloc] init];
    sample.presentationTimestamp = (double)(pts.value) / (double)(pts.timescale) - self.startSystemUptime;
    sample.red = r / 255.0;
    sample.green = g / 255.0;
    sample.blue = b / 255.0;
    sample.redSD = redSD;
    sample.redMean = redMean;
    #if !TARGET_IPHONE_SIMULATOR
    sample.isCoveringLens = isCoveringLens;
    #else
    sample.isCoveringLens = YES;
    #endif

    // Alert the delegate
    dispatch_async(_delegateCallbackQueue, ^{
        [self->_delegate processor:self didCaptureSample:sample];
    });
    
    return isCoveringLens;
}

#pragma mark - Video recording

// Adapted from https://developer.apple.com/library/content/samplecode/RosyWriter

- (void)startRecordingToURL:(NSURL *)url startTime:(CMTime)time formatDescription:(CMFormatDescriptionRef)formatDescription {
    NSParameterAssert(url != nil);
    NSParameterAssert(formatDescription != nil);
    NSLog(@"Starting video recording to %@", url);
    
    @synchronized(self) {
        if (_status != MovieRecorderStatusIdle) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Already prepared, cannot prepare again" userInfo:nil];
            return;
        }
        
        [self transitionToStatus:MovieRecorderStatusPreparingToRecord error:nil];
        _videoURL = url;
    }
    
    dispatch_async(_processingQueue, ^{
        @autoreleasepool {
            
            NSError *error = nil;
            // AVAssetWriter will not write over an existing file.
            [[NSFileManager defaultManager] removeItemAtURL:self->_videoURL error:NULL];
            
            // Open a new asset writer
            self->_assetWriter = [[AVAssetWriter alloc] initWithURL:self->_videoURL fileType:AVFileTypeQuickTimeMovie error:&error];
            
            // Create and add inputs
            if (!error) {
                [self setupAssetWriterVideoInputWithSourceFormatDescription:formatDescription error:&error];
            }
            
            if (!error) {
                BOOL success = [self->_assetWriter startWriting];
                if (!success) {
                    error = self->_assetWriter.error;
                } else {
                    [self->_assetWriter startSessionAtSourceTime:time];
                }
            }
            
            @synchronized(self) {
                if (error) {
                    [self transitionToStatus:MovieRecorderStatusFailed error:error];
                } else {
                    [self transitionToStatus:MovieRecorderStatusRecording error:nil];
                }
            }
        }
    } );
}

// call under @synchonized(self)
- (void)transitionToStatus:(MovieRecorderStatus)newStatus error:(NSError *)error {
    if (newStatus == _status) { return; }

    // terminal states
    BOOL isTerminalStatus = (newStatus == MovieRecorderStatusFinished) || (newStatus == MovieRecorderStatusFailed);
    if (isTerminalStatus) {
        // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
        dispatch_async(_processingQueue, ^{
            [self teardownAssetWriterAndInputs];
            if (newStatus == MovieRecorderStatusFailed) {
                [[NSFileManager defaultManager] removeItemAtURL:self->_videoURL error:NULL];
                self->_videoURL = nil;
            }
        });
    }
    
    // Update the status
    _status = newStatus;
    
    BOOL shouldNotifyDelegate = isTerminalStatus || (newStatus == MovieRecorderStatusRecording);
    if (shouldNotifyDelegate) {
        dispatch_async(_delegateCallbackQueue, ^{
            @autoreleasepool {
                switch (newStatus) {
                    case MovieRecorderStatusFailed:
                    if ([self->_delegate respondsToSelector:@selector(processor:didFailToRecordWithError:)]) {
                        [self->_delegate processor:self didFailToRecordWithError:error];
                        }
                        break;
                    default:
                        break;
                }
            }
        });
    }
}

- (void)stopRecordingWithCompletion:(void (^)(void))completion {
    @synchronized(self) {
        BOOL shouldFinishRecording = NO;
        switch (_status) {
            case MovieRecorderStatusIdle:
            case MovieRecorderStatusPreparingToRecord:
            case MovieRecorderStatusFinishingRecordingPart1:
            case MovieRecorderStatusFinishingRecordingPart2:
            case MovieRecorderStatusFinished:
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Not recording" userInfo:nil];
                break;
            case MovieRecorderStatusFailed:
                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when finishRecording is called and we are in an error state.
                break;
            case MovieRecorderStatusRecording:
                shouldFinishRecording = YES;
                break;
        }
        
        if (shouldFinishRecording) {
            [self transitionToStatus:MovieRecorderStatusFinishingRecordingPart1 error:nil];
        }
        else {
            return;
        }
    }
    
    dispatch_async(_processingQueue, ^{
        @autoreleasepool {
            @synchronized(self) {
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if (self->_status != MovieRecorderStatusFinishingRecordingPart1) {
                    return;
                }
                
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more
                // buffers will be appended.
                [self transitionToStatus:MovieRecorderStatusFinishingRecordingPart2 error:nil];
            }
            
            [self->_assetWriter finishWritingWithCompletionHandler:^{
                @synchronized(self) {
                    NSError *error = self->_assetWriter.error;
                    if (error) {
                        [self transitionToStatus:MovieRecorderStatusFailed error:error];
                    } else {
                        [self transitionToStatus:MovieRecorderStatusFinished error:nil];
                    }
                }
                
                if (completion) {
                    completion();
                }
            }];
        }
    });
}

- (BOOL)setupAssetWriterVideoInputWithSourceFormatDescription:(CMFormatDescriptionRef)videoFormatDescription error:(NSError **)errorOut {
    
    // Setup the video settings
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(videoFormatDescription);
    int numPixels = dimensions.width * dimensions.height;
    float bitsPerPixel = 4.05; // This bitrate approximately matches the quality produced by AVCaptureSessionPresetLow.
    int bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(bitsPerSecond),
                                             AVVideoExpectedSourceFrameRateKey : @(_frameRate),
                                             AVVideoMaxKeyFrameIntervalKey : @(_frameRate) };
    
    NSDictionary *videoSettings = @{ AVVideoCodecKey : AVVideoCodecTypeH264,
                       AVVideoWidthKey : @(dimensions.width),
                       AVVideoHeightKey : @(dimensions.height),
                       AVVideoCompressionPropertiesKey : compressionProperties };
    
    if ([_assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
        _videoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoSettings sourceFormatHint:videoFormatDescription];
        _videoInput.expectsMediaDataInRealTime = YES;
        _videoInput.transform = CGAffineTransformIdentity;
        
        if ([_assetWriter canAddInput:_videoInput]) {
            [_assetWriter addInput:_videoInput];
        }
        else {
            if (errorOut) {
                *errorOut = [[self class] cannotSetupInputError];
            }
            return NO;
        }
    }
    else {
        if (errorOut) {
            *errorOut = [[self class] cannotSetupInputError];
        }
        return NO;
    }
    
    return YES;
}

+ (NSError *)cannotSetupInputError {
    NSString *localizedDescription = NSLocalizedString( @"Recording cannot be started", nil);
    NSString *localizedFailureReason = NSLocalizedString( @"Cannot setup asset writer input.", nil);
    NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : localizedDescription,
                                 NSLocalizedFailureReasonErrorKey : localizedFailureReason };
    return [NSError errorWithDomain:@"io.carechain.HeartRateProcessor" code:-1 userInfo:errorDict];
}

- (void)teardownAssetWriterAndInputs {
    _videoInput = nil;
    _assetWriter = nil;
}

@end
