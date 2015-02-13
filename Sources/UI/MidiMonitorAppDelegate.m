//
//  MidiMonitorAppDelegate.m
//  MidiMonitor
//
//  Created by Pete Goodliffe on 10/14/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "MidiMonitorAppDelegate.h"

#import "MidiMonitorViewController.h"
#import "PGMidi.h"
#import "PGArc.h"

@implementation MidiMonitorAppDelegate

@synthesize window;
@synthesize viewController;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [window addSubview:viewController.view];
    [window makeKeyAndVisible];

    // We only create a MidiInput object on iOS versions that support CoreMIDI
    midi                            = [[PGMidi alloc] init];
    midi.networkEnabled             = YES;
    viewController.midi             = midi;
    midi.virtualDestinationEnabled  = YES;
    midi.virtualSourceEnabled       = YES;

	return YES;
}

@end
