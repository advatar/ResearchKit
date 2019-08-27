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


#import "ORKHeartRateStepViewController.h"

#import "ORKActiveStepTimer.h"
#import "ORKActiveStepView.h"
#import "ORKHeartRateContentView.h"
#import "ORKCustomStepView_Internal.h"
#import "ORKVerticalContainerView.h"

#import "ORKActiveStepViewController_Internal.h"
#import "ORKHeartRateRecorder.h"

#import "ORKHeartRateStep.h"
#import "ORKStep_Private.h"

#import "ORKHeartRateResult.h"
#import "ORKResult_Private.h"
#import "ORKCollectionResult_Private.h"

#import "ORKHelpers_Internal.h"

@import AVFoundation;


@interface ORKHeartRateStepViewController () <OCKHeartRateRecorderDelegate>

//@property (nonatomic, strong) AVAudioRecorder *avAudioRecorder;

@end


@implementation ORKHeartRateStepViewController  {
    ORKHeartRateContentView *_heartRateContentView;
    ORKHeartRateRecorder *_heartRateRecorder;
    ORKActiveStepTimer *_timer;
    dispatch_queue_t _heartRateQueue;

    ORKHeartRateResult *_localResult;
    NSError *_heartRateRecorderError;
}

- (instancetype)initWithStep:(ORKStep *)step {
    self = [super initWithStep:step];
    if (self) {
        // Continue audio recording in the background
        self.suspendIfInactive = NO;
    }
    return self;
}

- (void)setAlertThreshold:(CGFloat)alertThreshold {
    _alertThreshold = alertThreshold;
    if (self.isViewLoaded && alertThreshold > 0) {
        _heartRateContentView.alertThreshold = alertThreshold;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _heartRateContentView = [ORKHeartRateContentView new];
    _heartRateContentView.timeLeft = self.heartRateStep.stepDuration;

    if (self.alertThreshold > 0) {
        _heartRateContentView.alertThreshold = self.alertThreshold;
    }
    self.activeStepView.activeCustomView = _heartRateContentView;

    _localResult = [[ORKHeartRateResult alloc] initWithIdentifier:self.step.identifier];

    _heartRateQueue = dispatch_queue_create("HeartRateQueue", DISPATCH_QUEUE_SERIAL);

}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    //[[UIApplication sharedApplication] setIdleTimerDisabled:YES];
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    //[[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

- (void)heartRateRecorderDidChange {

    //_heartRateRecorder.audioRecorder.meteringEnabled = YES;
    //[self setAvAudioRecorder: _heartRateRecorder.audioRecorder];

}

- (void)recordersDidChange {
    ORKHeartRateRecorder *heartRateRecorder = nil;
    for (ORKRecorder *recorder in self.recorders) {
        if ([recorder isKindOfClass:[ORKHeartRateRecorder class]]) {
            heartRateRecorder = (ORKHeartRateRecorder *)recorder;
            break;
        }
    }
    _heartRateRecorder = heartRateRecorder;
    _heartRateRecorder.crfDelegate = self;
    [self heartRateRecorderDidChange];
}

- (ORKHeartRateStep *)heartRateStep {
    return (ORKHeartRateStep *)self.step;
}

- (ORKStepResult *)result {
    ORKStepResult *sResult = [super result];
    if (_heartRateQueue) {
        dispatch_sync(_heartRateQueue, ^{
            if (_localResult != nil) {

#if TARGET_IPHONE_SIMULATOR
                _localResult.bpm  = 61;
                _localResult.hrv  = 147;
#endif
                NSLog(@"_localResult %@\n",_localResult);

                NSMutableArray *results = [NSMutableArray arrayWithArray:sResult.results];
                [results addObject:_localResult];
                sResult.results = [results copy];
            }
        });
    }
    return sResult;
}

- (void)doSample {

#if TARGET_IPHONE_SIMULATOR
    BOOL isSimulator = YES;
#else
    BOOL isSimulator = NO;
#endif

    //NSString *modelName = [[UIDevice currentDevice] name];

 //   if ([modelName hasSuffix:@"Simulator"]) {
    if (isSimulator) {
        double value = (double)arc4random_uniform(100)/100.0;
        _bpm = 62 + arc4random_uniform(5);
        _hrv = 120 + arc4random_uniform(40);
        [_heartRateContentView addSample:@(-value)];
        _heartRateContentView.timeLeft = [_timer duration] - [_timer runtime];
        _heartRateContentView.bpm = _bpm;
        _heartRateContentView.isCoveringLens = YES; // _sample.isCoveringLens;
        return;
    } else if (_heartRateRecorderError) {
        return;
    }

    if (_sample ) {
        double v = (_sample.red - 0.85)*100.0 ;
        //NSLog(@"_sample.red %f %f\n", _sample.red, value);
        if (_sample.isCoveringLens /*&& ( (_sample.red > 0.5 &&  _sample.red < 0.999 && fabs(value) < 2.5) || (_sample.red > 0.5 && _sample.red > 0.99 && fabs(value) > 14.0  )  )*/) {
            //NSLog(@"adding %f \n", value);
            [_heartRateContentView addSample:@(-v)];
        }

        _heartRateContentView.timeLeft = [_timer duration] - [_timer runtime];
        _heartRateContentView.bpm = (int)_bpm;
        _heartRateContentView.isCoveringLens = YES; // _sample.isCoveringLens;
    }

}

- (void)startNewTimerIfNeeded {
    if (!_timer) {
        NSTimeInterval duration = self.heartRateStep.stepDuration;
        ORKWeakTypeOf(self) weakSelf = self;
        _timer = [[ORKActiveStepTimer alloc] initWithDuration:duration interval:duration / 6000 runtime:0 handler:^(ORKActiveStepTimer *timer, BOOL finished) {
            ORKStrongTypeOf(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf doSample];
                if (finished) {
                    [strongSelf finish];
                }
            }
        }];
        [_timer resume];
    }
    _heartRateContentView.finished = NO;
}

- (void)start {

    [super start];
    [self heartRateRecorderDidChange];
    [_timer reset];
    _timer = nil;
    [self startNewTimerIfNeeded];
    [_heartRateRecorder start];
}

- (void)suspend {
    [super suspend];
    [_timer pause];
    /*
    if (_avAudioRecorder) {
        [_heartRateContentView addSample:@(0)];
    }*/
}

- (void)resume {
    [super resume];
    [self heartRateRecorderDidChange];
    [self startNewTimerIfNeeded];
    [_timer resume];
}

- (void)finish {
    if (_heartRateRecorderError) {
        return;
    }
    [super finish];
    [_timer reset];
    _timer = nil;
    [_heartRateRecorder stop];
}

- (void)stepDidFinish {
    NSLog(@"stepDidFinish\n");
    _heartRateContentView.finished = YES;
}

- (void)recorder:(ORKRecorder *)recorder didFailWithError:(NSError *)error {
    [super recorder:recorder didFailWithError:error];
     NSLog(@"didFailWithError: %@\n", error);
    _heartRateRecorderError = error;
    if (error.code != 260) { // ignore Error Domain=NSCocoaErrorDomain Code=260 "No collected data was found." UserInfo={NSLocalizedDescription=No collected data was found.
        _heartRateContentView.failed = YES;
    }
}

- (void)recorder:(nonnull ORKRecorder *)recorder didCompleteWithResult:(nullable ORKResult *)result {
     NSLog(@"didCompleteWithResult: %@\n", result);

    _bpm = round([_heartRateRecorder restingHeartRate].bpm);
    _hrv = [_heartRateRecorder hrvSDNN];

    _localResult.bpm = _bpm;
    _localResult.hrv  = _hrv;

    _heartRateContentView.failed = NO;
}


- (void)didFinishStartingCamera {
    //NSLog(@"didFinishStartingCamera");
}

- (UIView *)previewView {
    //NSLog(@"processorPreviewView");
    return nil;
}


- (void)updateBPM:(double)bpm {
    //NSLog(@"bpm %f",bpm);
    _bpm = bpm;
}

- (void)updateSample:(CRFPixelSample *)sample {
    _sample = sample;

    /*
    if (_sample.isCoveringLens) {
        [self suspend];
    } else {
        [self resume];
    }*/

}


@end
