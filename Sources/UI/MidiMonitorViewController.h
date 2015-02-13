//
//  MidiMonitorViewController.h
//  MidiMonitor
//
//  Created by Pete Goodliffe on 10/14/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PGMidi;

@interface MidiMonitorViewController : UIViewController
{
    UILabel    *countLabel;
    UITextView *textView;

    PGMidi *midi;
}

@property (nonatomic,strong) IBOutlet UILabel    *countLabel;
@property (nonatomic,strong) IBOutlet UITextView *textView;

@property (nonatomic,strong) PGMidi *midi;

- (IBAction) clearTextView;
- (IBAction) listAllInterfaces;
- (IBAction) sendMidiData;

@end

