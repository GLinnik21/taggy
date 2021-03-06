//
//  TGCurrency.h
//  Taggy
//
//  Created by Nikolay Volosatov on 01.11.14.
//  Copyright (c) 2014 Gleb Linkin. All rights reserved.
//

#import <Realm/Realm.h>
#import <UIKit/UIKit.h>

@interface TGCurrency : RLMObject

@property NSString *code;
@property NSDate *updateDate;
@property CGFloat value;

+ (TGCurrency *)currencyForCode:(NSString *)code;

@end

// RLMArray<TGCurrency>
RLM_ARRAY_TYPE(TGCurrency)
