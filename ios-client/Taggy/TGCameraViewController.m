//
//  ViewController.m
//  IPDFCameraViewController
//
//  Created by Maximilian Mackh on 11/01/15.
//  Copyright (c) 2015 Maximilian Mackh. All rights reserved.
//

#import "TGCameraViewController.h"
#import "TGImageRecognizerHelper.h"
#import "TGSettingsManager.h"

#import "IPDFCameraViewController.h"

#import <SVProgressHUD/SVProgressHUD.h>
#import <ARAnalytics/ARAnalytics.h>
#import <Masonry/Masonry.h>

@interface TGCameraViewController ()

@property (weak, nonatomic) IBOutlet IPDFCameraViewController *cameraViewController;
@property (weak, nonatomic) IBOutlet UIImageView *focusIndicator;
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UIButton *cropButton;

- (IBAction)focusGesture:(id)sender;
- (IBAction)captureButton:(id)sender;

@end

@implementation TGCameraViewController

#pragma mark -
#pragma mark View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    BOOL borderDetection = [[TGSettingsManager objectForKey:kTGSettingsBorderDetectionKey] boolValue];

    [self.cameraViewController setupCameraView];
    [self.cameraViewController setEnableBorderDetection:borderDetection];
    [self.cameraViewController setCameraViewType:IPDFCameraViewTypeNormal];

    [self.cameraViewController mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(self.cameraViewController.mas_height).multipliedBy(3.0f / 4.0f);
        make.size.lessThanOrEqualTo(self.view);
        make.size.equalTo(self.view).with.priorityHigh();
        make.center.equalTo(self.view);
    }];

    [self.flashButton setImage:[UIImage imageNamed:@"flash_off"] forState:UIControlStateNormal];
    [self.flashButton setTitle:NSLocalizedString(@"flash_off", @"Off") forState:UIControlStateNormal];

    [self makeCropEnabled:borderDetection];

    if (self.cameraViewController.legacyMode) {
        self.cropButton.hidden = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.cameraViewController start];
    [ARAnalytics pageView:@"Camera"];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

#pragma mark -
#pragma mark CameraVC Actions

- (IBAction)focusGesture:(UITapGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        CGPoint location = [sender locationInView:self.cameraViewController];

        [self focusIndicatorAnimateToPoint:location];

        [self.cameraViewController focusAtPoint:location completionHandler:^{
             [self focusIndicatorAnimateToPoint:location];
        }];
    }
}

- (void)focusIndicatorAnimateToPoint:(CGPoint)targetPoint
{
    [self.focusIndicator setCenter:targetPoint];
    self.focusIndicator.alpha = 0.0;
    self.focusIndicator.hidden = NO;

    [UIView animateWithDuration:1.0 animations:^{
        self.focusIndicator.alpha = 1.0;
    }
        completion:^(BOOL finished) {
                         [UIView animateWithDuration:1.0 animations:^
                          {
                              self.focusIndicator.alpha = 0.0;
                          }];
        }];
}

- (IBAction)borderDetectToggle:(id)sender
{
    BOOL enable = self.cameraViewController.isBorderDetectionEnabled == NO;
    [self makeCropEnabled:enable];
    [TGSettingsManager setObject:@(enable) forKey:kTGSettingsBorderDetectionKey];
}

- (void)makeCropEnabled:(BOOL)enabled
{
    if (enabled) {
        [self.cropButton setImage:[UIImage imageNamed:@"crop_on"] forState:UIControlStateNormal];
        [self.cropButton setTitle:NSLocalizedString(@"flash_on", @"On") forState:UIControlStateNormal];
        [self.cropButton setTitleColor:[UIColor colorWithRed:1 green:0.81 blue:0 alpha:1] forState:UIControlStateNormal];
    }
    else {
        [self.cropButton setImage:[UIImage imageNamed:@"crop_off"] forState:UIControlStateNormal];
        [self.cropButton setTitle:NSLocalizedString(@"flash_off", @"Off") forState:UIControlStateNormal];
        [self.cropButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    self.cameraViewController.enableBorderDetection = enabled;
}

- (IBAction)torchToggle:(id)sender
{
    BOOL enable = !self.cameraViewController.isTorchEnabled;
    if (enable) {
        [self.flashButton setImage:[UIImage imageNamed:@"flash_on"] forState:UIControlStateNormal];
        [self.flashButton setTitle:NSLocalizedString(@"flash_on", @"On") forState:UIControlStateNormal];
        [self.flashButton setTitleColor:[UIColor colorWithRed:1 green:0.81 blue:0 alpha:1] forState:UIControlStateNormal];
    }
    else {
        [self.flashButton setImage:[UIImage imageNamed:@"flash_off"] forState:UIControlStateNormal];
        [self.flashButton setTitle:NSLocalizedString(@"flash_off", @"Off") forState:UIControlStateNormal];
        [self.flashButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    self.cameraViewController.enableTorch = enable;
}

- (void)changeButton:(UIButton *)button targetTitle:(NSString *)title toStateEnabled:(BOOL)enabled
{
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:(enabled ? [UIColor colorWithRed:1 green:0.81 blue:0 alpha:1] : [UIColor whiteColor])
                 forState:UIControlStateNormal];
}

#pragma mark -
#pragma mark CameraVC Capture Image

- (IBAction)captureButton:(id)sender
{
    [self.cameraViewController captureImageWithCompletionHander:^(id data) {
        UIImage *image = ([data isKindOfClass:[NSData class]]) ? [UIImage imageWithData:data] : data;

        [ARAnalytics event:@"Photo takken"];

        [TGImageRecognizerHelper recognizeImage:image navigationController:self.tabNavigationController];

        [self dismissViewControllerAnimated:YES completion:nil];
    }];
}

- (IBAction)dismiss:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [self.cameraViewController stop];
    [SVProgressHUD dismiss];

    [super viewDidDisappear:animated];
}

@end
