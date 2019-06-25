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


@import Foundation;
#import <ResearchKit/ORKFormStep.h>


NS_ASSUME_NONNULL_BEGIN

/**
 The `ORKProfileStepOption` flags let you include particular fields in addition
 to the default fields in the Profile step.
 */
typedef NS_OPTIONS(NSUInteger, ORKProfileStepOption) {
    /// Default behavior.
    ORKProfileStepDefault = 0,
    
    /// Include the given name field.
    ORKProfileStepIncludeGivenName = (1 << 1),
    
    /// Include the family name field.
    ORKProfileStepIncludeFamilyName = (1 << 2),
    
    /// Include the gender field.
    ORKProfileStepIncludeGender = (1 << 3),
    
    /// Include the date of birth field.
    ORKProfileStepIncludeDOB = (1 << 4)
} ORK_ENUM_AVAILABLE;


/**
 Constants for the form items included in the Profile step.
 These allow for convenient retrieval of user's inputted data from the result.
 */
ORK_EXTERN NSString *const ORKProfileFormItemIdentifierGivenName ORK_AVAILABLE_DECL;
ORK_EXTERN NSString *const ORKProfileFormItemIdentifierFamilyName ORK_AVAILABLE_DECL;
ORK_EXTERN NSString *const ORKProfileFormItemIdentifierGender ORK_AVAILABLE_DECL;
ORK_EXTERN NSString *const ORKProfileFormItemIdentifierDOB ORK_AVAILABLE_DECL;


/**
 The `ORKProfileStep` class represents a form step that provides fields commonly used
 for account Profile.
 
Optionally, any of the additional fields can be included based on context and requirements.
 */
ORK_CLASS_AVAILABLE
@interface ORKProfileStep : ORKFormStep

/**
 Returns an initialized Profile step using the specified identifier,
 title, text, options.
 
 @param identifier                              The string that identifies the step (see `ORKStep`).
 @param title                                   The title of the form (see `ORKStep`).
 @param text                                    The text shown immediately below the title (see `ORKStep`).
  @param options                                 The options used for the step (see `ORKProfileStepOption`).
 
 @return An initialized Profile step object.
 */
- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(nullable NSString *)title
                              text:(nullable NSString *)text
                           options:(ORKProfileStepOption)options;


/**
 The options used for the step.
 
 These options allow one or more fields to be included in the Profile step.
 */
@property (nonatomic, readonly) ORKProfileStepOption options;


@end

NS_ASSUME_NONNULL_END
