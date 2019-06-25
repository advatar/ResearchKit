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


#import "ORKProfileStep.h"

#import "ORKAnswerFormat_Private.h"

#import "ORKHelpers_Internal.h"


NSString *const ORKProfileFormItemIdentifierGivenName = @"ORKProfileFormItemGivenName";
NSString *const ORKProfileFormItemIdentifierFamilyName = @"ORKProfileFormItemFamilyName";
NSString *const ORKProfileFormItemIdentifierGender = @"ORKProfileFormItemGender";
NSString *const ORKProfileFormItemIdentifierDOB = @"ORKProfileFormItemDOB";


static id ORKFindInArrayByFormItemId(NSArray *array, NSString *formItemIdentifier) {
    return ORKFindInArrayByKey(array, @"identifier", formItemIdentifier);
}

static NSArray <ORKFormItem*> *ORKProfileFormItems(ORKProfileStepOption options) {
    NSMutableArray *formItems = [NSMutableArray new];

    if (options & ORKProfileStepIncludeGivenName) {
        ORKTextAnswerFormat *answerFormat = [ORKAnswerFormat textAnswerFormat];
        answerFormat.multipleLines = NO;
        
        ORKFormItem *item = [[ORKFormItem alloc] initWithIdentifier:ORKProfileFormItemIdentifierGivenName
                                                               text:ORKLocalizedString(@"CONSENT_NAME_GIVEN", nil)
                                                       answerFormat:answerFormat
                                                           optional:NO];
        item.placeholder = ORKLocalizedString(@"GIVEN_NAME_ITEM_PLACEHOLDER", nil);
        
        [formItems addObject:item];
    }
    
    if (options & ORKProfileStepIncludeFamilyName) {
        ORKTextAnswerFormat *answerFormat = [ORKAnswerFormat textAnswerFormat];
        answerFormat.multipleLines = NO;
        
        ORKFormItem *item = [[ORKFormItem alloc] initWithIdentifier:ORKProfileFormItemIdentifierFamilyName
                                                               text:ORKLocalizedString(@"CONSENT_NAME_FAMILY", nil)
                                                       answerFormat:answerFormat
                                                           optional:NO];
        item.placeholder = ORKLocalizedString(@"FAMILY_NAME_ITEM_PLACEHOLDER", nil);
        
        [formItems addObject:item];
    }
    
    // Adjust order of given name and family name form item cells based on current locale.
    if ((options & ORKProfileStepIncludeGivenName) && (options & ORKProfileStepIncludeFamilyName)) {
        if (ORKCurrentLocalePresentsFamilyNameFirst()) {
            ORKFormItem *givenNameFormItem = ORKFindInArrayByFormItemId(formItems, ORKProfileFormItemIdentifierGivenName);
            ORKFormItem *familyNameFormItem = ORKFindInArrayByFormItemId(formItems, ORKProfileFormItemIdentifierFamilyName);
            [formItems exchangeObjectAtIndex:[formItems indexOfObject:givenNameFormItem]
                           withObjectAtIndex:[formItems indexOfObject:familyNameFormItem]];
        }
    }
    
    if (options & ORKProfileStepIncludeGender) {
        NSArray *textChoices = @[[ORKTextChoice choiceWithText:ORKLocalizedString(@"GENDER_FEMALE", nil) value:@"female"],
                                 [ORKTextChoice choiceWithText:ORKLocalizedString(@"GENDER_MALE", nil) value:@"male"],
                                 [ORKTextChoice choiceWithText:ORKLocalizedString(@"GENDER_OTHER", nil) value:@"other"]];
        ORKValuePickerAnswerFormat *answerFormat = [ORKAnswerFormat valuePickerAnswerFormatWithTextChoices:textChoices];
        
        ORKFormItem *item = [[ORKFormItem alloc] initWithIdentifier:ORKProfileFormItemIdentifierGender
                                                               text:ORKLocalizedString(@"GENDER_FORM_ITEM_TITLE", nil)
                                                       answerFormat:answerFormat
                                                           optional:NO];
        item.placeholder = ORKLocalizedString(@"GENDER_FORM_ITEM_PLACEHOLDER", nil);
        
        [formItems addObject:item];
    }
    
    if (options & ORKProfileStepIncludeDOB) {
        // Calculate default date (20 years from now).
        NSDate *defaultDate = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateByAddingUnit:NSCalendarUnitYear
                                                                       value:-20
                                                                      toDate:[NSDate date]
                                                                     options:(NSCalendarOptions)0];
        
        ORKDateAnswerFormat *answerFormat = [ORKAnswerFormat dateAnswerFormatWithDefaultDate:defaultDate
                                                                                 minimumDate:nil
                                                                                 maximumDate:[NSDate date]
                                                                                    calendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
        
        ORKFormItem *item = [[ORKFormItem alloc] initWithIdentifier:ORKProfileFormItemIdentifierDOB
                                                               text:ORKLocalizedString(@"DOB_FORM_ITEM_TITLE", nil)
                                                       answerFormat:answerFormat
                                                           optional:NO];
        item.placeholder = ORKLocalizedString(@"DOB_FORM_ITEM_PLACEHOLDER", nil);
        
        [formItems addObject:item];
    }
    
    return formItems;
}


@implementation ORKProfileStep

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                              text:(NSString *)text
                           options:(ORKProfileStepOption)options {
    self = [super initWithIdentifier:identifier title:title text:text];
    if (self) {
        _options = options;
        self.optional = NO;
    }
    return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                              text:(NSString *)text {
    return [self initWithIdentifier:identifier
                              title:title
                               text:text
                            options:ORKProfileStepDefault];
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
    return [self initWithIdentifier:identifier
                              title:nil
                               text:nil];
}

- (NSArray <ORKFormItem *> *)formItems {
    if (![super formItems]) {
        self.formItems = ORKProfileFormItems(_options);
    }
    
    ORKFormItem *dobFormItem = ORKFindInArrayByFormItemId([super formItems], ORKProfileFormItemIdentifierDOB);
    ORKDateAnswerFormat *originalAnswerFormat = (ORKDateAnswerFormat *)dobFormItem.answerFormat;
    ORKDateAnswerFormat *modifiedAnswerFormat = [ORKAnswerFormat dateAnswerFormatWithDefaultDate:originalAnswerFormat.defaultDate
                                                                                     minimumDate:originalAnswerFormat.minimumDate
                                                                                     maximumDate:[NSDate date]
                                                                                        calendar:originalAnswerFormat.calendar];

    dobFormItem = [[ORKFormItem alloc] initWithIdentifier:ORKProfileFormItemIdentifierDOB
                                                     text:ORKLocalizedString(@"DOB_FORM_ITEM_TITLE", nil)
                                             answerFormat:modifiedAnswerFormat
                                                 optional:NO];
    dobFormItem.placeholder = ORKLocalizedString(@"DOB_FORM_ITEM_PLACEHOLDER", nil);
    
    return [super formItems];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        
        ORK_DECODE_INTEGER(aDecoder, options);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    
    ORK_ENCODE_INTEGER(aCoder, options);
}

- (instancetype)copyWithZone:(NSZone *)zone {
    ORKProfileStep *step = [super copyWithZone:zone];
    
    step->_options = self.options;
    return step;
}

- (BOOL)isEqual:(id)object {
    BOOL isParentSame = [super isEqual:object];
    
    __typeof(self) castObject = object;
    return (isParentSame &&
            self.options == castObject.options);
}

@end
