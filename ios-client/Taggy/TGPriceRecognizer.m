//
//  TGPriceRecognizer.m
//  Taggy
//
//  Created by Nikolay Volosatov on 30.10.14.
//  Copyright (c) 2014 Gleb Linkin. All rights reserved.
//

#import "TGPriceRecognizer.h"
#import <TesseractOCR/Tesseract.h>
#import <CoreImage/CoreImage.h>

static NSString *const kTGNumberRegexPattern = @"([0-9]*|[0-9]+[,.])([,.][0-9]+|[0-9]+)";

static CGFloat const kTGMinimalBlockConfidence = 10.0f;
static CGFloat const kTGMinimalBlockHeight = 20.0f;
static CGFloat const kTGHorisontalJoinDistance = 15.0f;
static CGFloat const kTGMaximumVerticalDelta = 10.0f;

@interface TGPriceRecognizer()

@property (nonatomic, strong) NSArray *recognizedBlocks;
@property (nonatomic, strong) NSArray *recognizedPrices;

@property (nonatomic, strong) Tesseract *tesseract;
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
        _tesseract = [[Tesseract alloc] initWithLanguage:language];
    }
    return self;
}

- (void)setImage:(UIImage *)image
{
    if (_image != image) {
        _image = [[self imageWithImage:image scaledToSizeWithSameAspectRatio:CGSizeMake(500, 500)] blackAndWhite];

        self.tesseract.image = _image;
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
    @try {
        [self clear];

        [self.tesseract recognize];
        self.recognizedBlocks = [TGRecognizedBlock blocksFromRecognitionArray:self.tesseract.getConfidenceByWord];
        self.wellRecognizedBlocks = self.recognizedBlocks;

        //[self removeBadRecognizedBlocks];
        [self splitBlocks];
        //[self removeSmallBlocks];
        [self sortBlocks];
        [self joinBlocks];

        [self formatPrices];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@", exception.description);
        [self clear];
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

                TGRecognizedBlock *unionedResult = nil;
                if (topDelta < kTGMaximumVerticalDelta && bottomDelta < kTGMaximumVerticalDelta) {
                    if (leftDistDelta > kTGHorisontalJoinDistance || rightDistDelta > kTGHorisontalJoinDistance) {
                        if (leftDistDelta < kTGHorisontalJoinDistance) {
                            NSLog(@"new word: %@ + %@", exBlock.text, block.text);
                            unionedResult =
                                [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                               confidence:MIN(exBlock.confidence, block.confidence)
                                                                     text:[exBlock.text stringByAppendingString:block.text]];
                        }
                        else if (rightDistDelta < kTGHorisontalJoinDistance) {
                            NSLog(@"new word: %@ + %@", block.text, exBlock.text);
                            unionedResult =
                                [[TGRecognizedBlock alloc] initWithRegion:CGRectUnion(exBlock.region, block.region)
                                                               confidence:MIN(exBlock.confidence, block.confidence)
                                                                     text:[block.text stringByAppendingString:exBlock.text]];
                        }
                    }
                }

                if (unionedResult != nil) {
                    [newGoodWords removeObject:block];
                    [newGoodWords removeObject:exBlock];
                    [newGoodWords addObject:unionedResult];

                    anyFound = YES;
                }
            }
        }
        self.wellRecognizedBlocks = newGoodWords;
    } while (anyFound);
}

- (void)formatPrices
{
    NSMutableArray *results = [[NSMutableArray alloc] initWithCapacity:self.wellRecognizedBlocks.count];
    for (TGRecognizedBlock *block in self.wellRecognizedBlocks) {
        [results addObject:[block number]];
    }

    self.recognizedPrices = results;
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

- (UIImage*)imageWithImage:(UIImage*)sourceImage scaledToSizeWithSameAspectRatio:(CGSize)targetSize
{
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = targetSize.width;
    CGFloat targetHeight = targetSize.height;

    CGFloat scaleFactor = 1.0f;
    CGFloat scaledWidth = targetWidth;
    CGFloat scaledHeight = targetHeight;

    if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;

        if (widthFactor < heightFactor) {
            scaleFactor = widthFactor;
        }
        else {
            scaleFactor = heightFactor;
        }

        scaledWidth  = width * scaleFactor;
        scaledHeight = height * scaleFactor;
    }

    UIGraphicsBeginImageContext(CGSizeMake(scaledWidth, scaledHeight));
    [sourceImage drawInRect: CGRectMake(0, 0, scaledWidth, scaledHeight)];
    UIImage *smallImage = UIGraphicsGetImageFromCurrentImageContext();
    
    return smallImage;
}

@end
