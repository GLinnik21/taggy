//
//  TGAppDelegate.m
//  Taggy
//
//  Created by Gleb Linkin on 9/29/14.
//  Copyright (c) 2014 Gleb Linkin. All rights reserved.
//

#import "TGAppDelegate.h"
#import <ARAnalytics/ARAnalytics.h>
#import "TGDataManager.h"
#import "TGCurrencyManager.h"
#import "TGMigrationManager.h"

@interface TGAppDelegate ()

@end

@implementation TGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [ARAnalytics setupWithAnalytics:@{
                                      ARFlurryAPIKey : @"R28M5M82FH2X33XCQW4N",
                                      ARGoogleAnalyticsID : @"UA-9189602-6"
                                      }];

    [TGMigrationManager migrate];
    
    [TGCurrencyManager update];
    [TGDataManager fillSample];

    return YES;
}

@end
