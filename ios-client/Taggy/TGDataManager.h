//
//  TGDataManager.h
//  Taggy
//
//  Created by Nikolay Volosatov on 02.11.14.
//  Copyright (c) 2014 Gleb Linkin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TGPriceImage.h"

@interface TGDataManager : NSObject

+ (void)fillSample;

+ (NSInteger)recognizedImagesCount;
+ (TGPriceImage *)recognizedImageAtIndex:(NSInteger)index;
+ (BOOL)removeRecognizedImage:(TGPriceImage *)recognizedImage;
+ (BOOL)deleteAllObjects;

+ (void)recognizeImage:(UIImage *)image
          withCallback:(void (^)(TGPriceImage *priceImage))callback
              progress:(void (^)(CGFloat progress))progress;

+ (TGCurrency *)sourceCurrency;
+ (TGCurrency *)transferCurrency;

@end
