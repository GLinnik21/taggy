//
//  TGPriceRecognizer.m
//  Taggy
//
//  Created by Nikolay Volosatov on 30.10.14.
//  Copyright (c) 2014 Gleb Linkin. All rights reserved.
//

#import "TGPriceRecognizer.h"
#import "TGCommon.h"
#import <TesseractOCR/TesseractOCR.h>
#import <CoreImage/CoreImage.h>
#import <ARAnalytics/ARAnalytics.h>
#import <GPUImage/GPUImage.h>
#import "UIImage+FixOrientation.h"

#import "TGSettingsManager.h"

static NSString *const kTGNumberRegexPattern = @"(([0-9]*|[0-9]+[,.])([,.][0-9]+|[0-9]+)|[,.])";

static NSTimeInterval const kTGMaxRecognitionTime = 3.0;

static CGFloat const kTGMinimalBlockConfidence = 10.0f;
static CGFloat const kTGMinimalBlockHeight = 20.0f;
static CGFloat const kTGMaximalConfidenceDelta = 25.0f;
static NSUInteger const kTGMaximumPriceLength = 10;
static CGFloat const kTGMinimumPriceValue = 10.0f;
static NSUInteger const kTGMaximumPricesCount = 4;

@interface TGPriceRecognizer() <G8TesseractDelegate>

@property (nonatomic, strong) NSArray *recognizedBlocks;
@property (nonatomic, strong) NSArray *recognizedPrices;

@property (nonatomic, strong) G8Tesseract *tesseract;
@property (nonatomic, strong) NSArray *wellRecognizedBlocks;

@end

@implementation TGPriceRecognizer

- (id)init
{
    return [self initWithLanguage:@"rus"];
}

- (id)initWithLanguage:(NSString *)language
{
    self = [super init];
    if (self != nil) {
        _tesseract = [[G8Tesseract alloc] initWithLanguage:language];
        _tesseract.delegate = self;

        [_tesseract setVariablesFromDictionary:@{
            //kG8ParamTextordNoiseNormratio: @"5",
            kG8ParamTextordHeavyNr : @"1",
            //kG8ParamTesseditMinimalRejection : @"1",
            kG8ParamTextordParallelBaselines : @"0",
            kG8ParamClassifyBlnNumericMode : @"6",
            kG8ParamMatcherAvgNoiseSize : @"22",
            kG8ParamNumericPunctuation : @",.",
            kG8ParamTestPt : @"1",
        }];

        //_tesseract.charWhitelist = @"0123456789,.-";
        _tesseract.charBlacklist = @"|:?+=_{}[]%!@#^&*шШВвОобБтТ";
        _tesseract.pageSegmentationMode = G8PageSegmentationModeSparseText;
        _tesseract.maximumRecognitionTime = kTGMaxRecognitionTime;
    }
    return self;
}

+ (UIImage *)binarizeImage:(UIImage *)sourceImage andResize:(CGSize)size
{
    GPUImageFilterGroup *group = [[GPUImageFilterGroup alloc] init];

    /*GPUImageContrastFilter *contrast = [[GPUImageContrastFilter alloc] init];
    contrast.contrast = 2.0;
    [group addFilter:contrast];*/

    GPUImageLuminanceThresholdFilter *threshold = [[GPUImageLuminanceThresholdFilter alloc] init];
    threshold.threshold = 0.5f;
    //GPUImageAverageLuminanceThresholdFilter *threshold = [[GPUImageAverageLuminanceThresholdFilter alloc] init];
    //GPUImageAdaptiveThresholdFilter *threshold = [[GPUImageAdaptiveThresholdFilter alloc] init];
    //threshold.thresholdMultiplier = 1.0;
    [group addFilter:threshold];

    GPUImageLanczosResamplingFilter *resample = [[GPUImageLanczosResamplingFilter alloc] init];
    resample.originalImageSize = sourceImage.size;
    [resample forceProcessingAtSizeRespectingAspectRatio:size];
    [group addFilter:resample];

    //[contrast addTarget:threshold];
    [threshold addTarget:resample];

    [group setInitialFilters:@[ threshold ]];
    [group setTerminalFilter:resample];

    GPUImagePicture *stillImage = [[GPUImagePicture alloc] initWithImage:sourceImage];
    [group useNextFrameForImageCapture];
    [stillImage addTarget:group];
    [stillImage processImage];

    UIImage *resultImage = [group imageFromCurrentFramebufferWithOrientation:sourceImage.imageOrientation];
    return resultImage;
}

- (UIImage *)preprocessedImageForTesseract:(G8Tesseract *)tesseract sourceImage:(UIImage *)sourceImage
{
    sourceImage = [sourceImage fixOrientation];
    sourceImage = [[self class] binarizeImage:sourceImage andResize:CGSizeMake(800, 800)];

    return sourceImage;
}

- (void)progressImageRecognitionForTesseract:(G8Tesseract *)tesseract
{
    if (tesseract == self.tesseract) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;

            if (strongSelf.progressBlock != nil) {
                strongSelf.progressBlock(tesseract.progress / 100.0f);
            }
        });
    }
}

- (void)setImage:(UIImage *)image
{
    if (_image != image) {
        _image = [TGCommon imageWithImage:image scaledToSizeWithSameAspectRatio:CGSizeMake(800, 800)];

        self.tesseract.image = image;
    }
}

- (NSString *)recognizedPlainText
{
    return self.tesseract.recognizedText;
}

- (void)clear
{
    self.wellRecognizedBlocks = nil;
    self.recognizedPrices = nil;
}

- (void)recognize
{
    [ARAnalytics startTimingEvent:@"Recognizing image"];

    @try {
        [self clear];

        [self.tesseract recognize];

        NSArray *blocks = [self.tesseract recognizedBlocksByIteratorLevel:G8PageIteratorLevelWord];
        self.recognizedBlocks = [TGRecognizedBlock blocksFromRecognitionArray:blocks];
        self.wellRecognizedBlocks = self.recognizedBlocks;

        /*UIImage *tresholdedWords = [self.tesseract imageWithBlocks:blocks
                                                          drawText:YES
                                                       thresholded:YES];*/

        //[self removeBadRecognizedBlocks];
        [self splitBlocks];
        //[self removeSmallBlocks];
        [self sortBlocks];
        [self takeFirst:INT_MAX];
        if ([[TGSettingsManager objectForKey:kTGSettingsSourceCurrencyKey] isEqual:@"BYR"] == NO) {
            [self fixDots];
            //[self joinDots];
        }
        [self joinBlocks];
        [self removeBadPrices];

        if ([[TGSettingsManager objectForKey:kTGSettingsSourceCurrencyKey] isEqual:@"BYR"]) {
            [self belarusOptimization];
        }

        [self sortBlocks];
        [self takeFirst:kTGMaximumPricesCount];

        [self formatPrices];
        DDLogInfo(@"Prices: %@", self.recognizedPrices);

        [ARAnalytics event:@"Image recognized"];
    }
    @catch (NSException *exception) {
        DDLogError(@"Exception: %@", exception.description);

        [ARAnalytics error:[NSError errorWithDomain:@"Tesseract"
                                               code:NSExecutableRuntimeMismatchError
                                           userInfo:@{ @"description" : exception.description }]
               withMessage:@"Recognition exception"];

        [self clear];
    }
    @finally {
        [ARAnalytics finishTimingEvent:@"Recognizing image"];
    }
}

- (void)sortBlocks
{
    self.wellRecognizedBlocks = [self.wellRecognizedBlocks sortedArrayUsingComparator:
                                 ^NSComparisonResult(TGRecognizedBlock *obj1, TGRecognizedBlock *obj2) {
        return obj2.confidence - obj1.confidence;
    }];
}

- (void)splitBlocks
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        NSString *text = block.text;

        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kTGNumberRegexPattern
                                                                               options:0
                                                                                 error:&error];
        if (error == nil) {
            CGFloat deltaX = CGRectGetWidth(block.region) / block.text.length;

            [regex enumerateMatchesInString:text
                                    options:0
                                      range:NSMakeRange(0, text.length)
                                 usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                                     NSString *newText = [text substringWithRange:result.range];
                                     CGRect region =
                                         CGRectMake(CGRectGetMinX(block.region) + deltaX * result.range.location,
                                                    CGRectGetMinY(block.region),
                                                    deltaX * result.range.length,
                                                    CGRectGetHeight(block.region));

                                     TGRecognizedBlock *newBlock =
                                        [[TGRecognizedBlock alloc] initWithRegion:region
                                                                       confidence:block.confidence
                                                                             text:newText];
                                     [newBlocks addObject:newBlock];
            }];
        }
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)removeBadRecognizedBlocks
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if (block.confidence < kTGMinimalBlockConfidence) continue;

        [newBlocks addObject:block];
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)removeSmallBlocks
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if (ABS(CGRectGetHeight(block.region)) < kTGMinimalBlockHeight) continue;

        [newBlocks addObject:block];
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)fixDots
{
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if ([block.text isEqualToString:@","]) {
            block.text = @".";
        }
    }
}

- (void)joinDots
{
    BOOL anyFound = NO;
    do {
        anyFound = NO;
        NSMutableArray *newGoodWords = [[NSMutableArray alloc] initWithArray:self.wellRecognizedBlocks];
        for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
            if ([newGoodWords containsObject:block] == NO) continue;
            for (TGRecognizedBlock *exBlock in self.wellRecognizedBlocks) {
                if ([newGoodWords containsObject:exBlock] == NO) continue;
                if (block == exBlock) continue;
                if ([exBlock.text isEqualToString:@"."] == NO) continue;

                CGFloat leftDistDelta = ABS(CGRectGetMinX(block.region) - CGRectGetMaxX(exBlock.region));
                CGFloat rightDistDelta = ABS(CGRectGetMaxX(block.region) - CGRectGetMinX(exBlock.region));
                CGFloat confDelta = ABS(block.confidence - exBlock.confidence);

                if (confDelta > kTGMaximalConfidenceDelta) continue;

                CGFloat maxHDelta = MIN(CGRectGetHeight(block.region), CGRectGetHeight(exBlock.region)) * 0.85;
                if (leftDistDelta < maxHDelta && rightDistDelta < maxHDelta) continue;

                TGRecognizedBlock *unionedResult = nil;
                if (leftDistDelta < maxHDelta) {
                    DDLogVerbose(@"new word: %@ + %@", exBlock.text, block.text);
                    unionedResult =
                        [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                       confidence:MIN(exBlock.confidence, block.confidence)
                                                             text:[exBlock.text stringByAppendingString:block.text]];
                }
                else if (rightDistDelta < maxHDelta) {
                    DDLogVerbose(@"new word: %@ + %@", block.text, exBlock.text);
                    unionedResult =
                        [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                       confidence:MIN(exBlock.confidence, block.confidence)
                                                             text:[block.text stringByAppendingString:exBlock.text]];
                }

                if (unionedResult != nil) {
                    [newGoodWords removeObject:block];
                    [newGoodWords removeObject:exBlock];
                    [newGoodWords addObject:unionedResult];

                    anyFound = YES;
                    break;
                }
            }
        }
        self.wellRecognizedBlocks = newGoodWords;
    } while (anyFound);
}

- (void)joinBlocks
{
    BOOL anyFound = NO;
    do {
        anyFound = NO;
        NSMutableArray *newGoodWords = [[NSMutableArray alloc] initWithArray:self.wellRecognizedBlocks];
        for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
            if ([newGoodWords containsObject:block] == NO) continue;
            for (TGRecognizedBlock *exBlock in self.wellRecognizedBlocks) {
                if ([newGoodWords containsObject:exBlock] == NO) continue;
                if (block == exBlock) continue;

                CGFloat topDelta = ABS(CGRectGetMinY(block.region) - CGRectGetMinY(exBlock.region));
                CGFloat bottomDelta = ABS(CGRectGetMaxY(block.region) - CGRectGetMaxY(exBlock.region));
                CGFloat leftDistDelta = ABS(CGRectGetMinX(block.region) - CGRectGetMaxX(exBlock.region));
                CGFloat rightDistDelta = ABS(CGRectGetMaxX(block.region) - CGRectGetMinX(exBlock.region));
                CGFloat confDelta = ABS(block.confidence - exBlock.confidence);

                if (confDelta > kTGMaximalConfidenceDelta) continue;

                CGFloat maxVDelta = (CGRectGetHeight(block.region) + CGRectGetHeight(exBlock.region)) * 0.5;
                CGFloat maxHDelta = MIN(CGRectGetHeight(block.region), CGRectGetHeight(exBlock.region)) * 0.85;

                if (topDelta > maxVDelta || bottomDelta > maxVDelta) continue;
                if (leftDistDelta < maxHDelta && rightDistDelta < maxHDelta) continue;

                TGRecognizedBlock *unionedResult = nil;
                if (leftDistDelta < maxHDelta) {
                    DDLogVerbose(@"new word: %@ + %@", exBlock.text, block.text);
                    unionedResult =
                        [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                       confidence:MIN(exBlock.confidence, block.confidence)
                                                             text:[exBlock.text stringByAppendingString:block.text]];
                }
                else if (rightDistDelta < maxHDelta) {
                    DDLogVerbose(@"new word: %@ + %@", block.text, exBlock.text);
                    unionedResult =
                        [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                       confidence:MIN(exBlock.confidence, block.confidence)
                                                             text:[block.text stringByAppendingString:exBlock.text]];
                }

                if (unionedResult != nil) {
                    [newGoodWords removeObject:block];
                    [newGoodWords removeObject:exBlock];
                    [newGoodWords addObject:unionedResult];

                    anyFound = YES;
                    break;
                }
            }
        }
        self.wellRecognizedBlocks = newGoodWords;
    } while (anyFound);
}

- (void)removeBadPrices
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if (block.text.length > kTGMaximumPriceLength) continue;
        if ([[block number] floatValue] < kTGMinimumPriceValue) continue;

        [newBlocks addObject:block];
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)belarusOptimization
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if ([[block.text substringFromIndex:block.text.length-1] isEqualToString:@"0"] == NO) continue;

        [newBlocks addObject:block];
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)takeFirst:(NSUInteger)count
{
    NSMutableArray *newBlocks = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    CGFloat maxConfidence = ((TGRecognizedBlock *)self.wellRecognizedBlocks.firstObject).confidence;
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        if (count <= 0) break;
        if (ABS(block.confidence - maxConfidence) > kTGMaximalConfidenceDelta) break;

        [newBlocks addObject:block];
        --count;
    }
    self.wellRecognizedBlocks = newBlocks;
}

- (void)formatPrices
{
    self.recognizedPrices = self.wellRecognizedBlocks;
}

- (UIImage *)debugImage
{
    return [TGRecognizedBlock drawBlocks:self.wellRecognizedBlocks onImage:self.image];
}

+ (NSArray *)recognizeImage:(UIImage *)image
{
    TGPriceRecognizer *recognizer = [[TGPriceRecognizer alloc] init];
    recognizer.image = image;
    [recognizer recognize];
    
    return recognizer.recognizedPrices;
}

@end
