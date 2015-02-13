//
//  PGMidiAllSources.h
//  PGMidi
//

#import <Foundation/Foundation.h>

@class PGMidi;
@protocol PGMidiSourceDelegate;

@interface PGMidiAllSources : NSObject
{
    PGMidi                  *midi;
    id<PGMidiSourceDelegate> delegate;
}

@property (nonatomic,strong) PGMidi *midi;
@property (nonatomic,strong) id<PGMidiSourceDelegate> delegate;

@end
