//
//  PGMidi.m
//  PGMidi
//

#import "PGMidi.h"
#import <mach/mach_time.h>

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    #import <CoreMIDI/MIDINetworkSession.h>
#endif

/// A helper that NSLogs an error message if "c" is an error code
#define NSLogError(c,str) do{if (c) NSLog(@"Error (%@): %ld:%@", str, (long)c,[NSError errorWithDomain:NSMachErrorDomain code:c userInfo:nil]);}while(false)

NSString * const PGMidiSourceAddedNotification        = @"PGMidiSourceAddedNotification";
NSString * const PGMidiSourceRemovedNotification      = @"PGMidiSourceRemovedNotification";
NSString * const PGMidiDestinationAddedNotification   = @"PGMidiDestinationAddedNotification";
NSString * const PGMidiDestinationRemovedNotification = @"PGMidiDestinationRemovedNotification";
NSString * const PGMidiConnectionKey                  = @"connection";

//==============================================================================

static void PGMIDINotifyProc(const MIDINotification *message, void *refCon);
static void PGMIDIReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon);
static void PGMIDIVirtualDestinationReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon);

@interface PGMidi ()
- (void) scanExistingDevices;
@property (NS_NONATOMIC_IOSONLY, readonly) MIDIPortRef outputPort;
@property (nonatomic, retain) NSTimer *rescanTimer;
@end

//==============================================================================

static
NSString *NameOfEndpoint(MIDIEndpointRef ref)
{
    CFStringRef string = nil;
    OSStatus s = MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, ( CFStringRef*)&string);
    if ( s != noErr ) 
    {
        return @"Unknown name";
    }
    return (NSString*)CFBridgingRelease(string);
}

static
BOOL IsNetworkSession(MIDIEndpointRef ref)
{
    MIDIEntityRef entity = 0;
    MIDIEndpointGetEntity(ref, &entity);

    BOOL hasMidiRtpKey = NO;
    CFPropertyListRef properties = nil;
    OSStatus s = MIDIObjectGetProperties(entity, &properties, true);
    if (!s)
    {
        NSDictionary *dictionary = CFBridgingRelease(properties);
        hasMidiRtpKey = [dictionary valueForKey:@"apple.midirtp.session"] != nil;
    }

    return hasMidiRtpKey;
}

//==============================================================================

@implementation PGMidiConnection

@synthesize midi;
@synthesize endpoint;
@synthesize name;
@synthesize isNetworkSession;

- (instancetype) initWithMidi:(PGMidi*)m endpoint:(MIDIEndpointRef)e
{
    if ((self = [super init]))
    {
        midi                = m;
        endpoint            = e;
        name                = NameOfEndpoint(e);
        isNetworkSession    = IsNetworkSession(e);
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"< PGMidiConnection: name=%@ isNetwork=%s >",
            self.name, self.isNetworkSession ? "yes" : "no"];

}

@end

//==============================================================================

@interface PGMidiSource ()
@property (strong, nonatomic, readwrite) NSArray *delegates;
@end

@implementation PGMidiSource

- (instancetype) initWithMidi:(PGMidi*)m endpoint:(MIDIEndpointRef)e
{
    if ((self = [super initWithMidi:m endpoint:e]))
    {
        self.delegates = @[];
    }
    return self;
}
- (void)addDelegate:(id<PGMidiSourceDelegate>)delegate
{
    if (![_delegates containsObject:[NSValue valueWithPointer:(void*)delegate]])
    {
        self.delegates = [_delegates arrayByAddingObject:[NSValue valueWithPointer:(void*)delegate] /* avoid retain loop */];
    }
}

- (void)removeDelegate:(id<PGMidiSourceDelegate>)delegate
{
    NSMutableArray *mutableDelegates = [_delegates mutableCopy];
    [mutableDelegates removeObject:[NSValue valueWithPointer:(void*)delegate]];
    self.delegates = mutableDelegates;
}

// NOTE: Called on a separate high-priority thread, not the main runloop
- (void) midiRead:(const MIDIPacketList *)pktlist
{
    NSArray *delegates = self.delegates;
    for (NSValue *delegatePtr in delegates)
    {
        id<PGMidiSourceDelegate> delegate = (id<PGMidiSourceDelegate>)[delegatePtr pointerValue];
        [delegate midiSource:self midiReceived:pktlist];
    }
}

static
void PGMIDIReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon)
{
    @autoreleasepool
    {
        PGMidiSource *self = (__bridge PGMidiSource *)srcConnRefCon;
        [self midiRead:pktlist];
    }
}

static
void PGMIDIVirtualDestinationReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon)
{
    @autoreleasepool
    {
        PGMidi *midi = (__bridge PGMidi*)readProcRefCon;
        PGMidiSource *self = midi.virtualDestinationSource;
        [self midiRead:pktlist];
    }
}

@end

//==============================================================================

@implementation PGMidiDestination

- (instancetype) initWithMidi:(PGMidi*)m endpoint:(MIDIEndpointRef)e
{
    if ((self = [super initWithMidi:m endpoint:e]))
    {
    }
    return self;
}

-(void)flushOutput
{
    MIDIFlushOutput(self.endpoint);
}

- (void) sendBytes:(const UInt8*)bytes size:(UInt32)size
{
    assert(size < 65536);
    Byte packetBuffer[size+100];
    MIDIPacketList *packetList = (MIDIPacketList*)packetBuffer;
    MIDIPacket     *packet     = MIDIPacketListInit(packetList);
    packet = MIDIPacketListAdd(packetList, sizeof(packetBuffer), packet, 0, size, bytes);

    [self sendPacketList:packetList];
}

- (void) sendPacketList:(MIDIPacketList *)packetList
{
    // Send it
    OSStatus s = MIDISend(self.midi.outputPort, self.endpoint, packetList);
    NSLogError(s, @"Sending MIDI");
}

@end

//==============================================================================

@interface PGMidiVirtualSourceDestination : PGMidiDestination
@end

@implementation PGMidiVirtualSourceDestination

- (void) sendPacketList:(MIDIPacketList *)packetList
{
    // Assign proper timestamps to packetList
    MIDIPacket *packet = &packetList->packet[0];
    for (int i = 0; i < packetList->numPackets; i++)
    {
        if ( packet->timeStamp == 0 )
        {
            packet->timeStamp = mach_absolute_time();
        }
        packet = MIDIPacketNext(packet);
    }

    // Send it
    OSStatus s = MIDIReceived(self.endpoint, packetList);
    NSLogError(s, @"Sending MIDI");
}

@end

//==============================================================================

@interface PGMidi ()
{
    MIDIClientRef      client;
    MIDIPortRef        outputPort;
    MIDIPortRef        inputPort;
    MIDIEndpointRef    virtualSourceEndpoint;
    MIDIEndpointRef    virtualDestinationEndpoint;
}

@end

@implementation PGMidi

@synthesize delegate;
@synthesize sources,destinations;
@synthesize virtualSourceDestination,virtualDestinationSource,virtualEndpointName;
@dynamic    networkEnabled;

- (instancetype) init
{
    if ((self = [super init]))
    {
        sources      = [NSMutableArray new];
        destinations = [NSMutableArray new];

        OSStatus s = MIDIClientCreate((CFStringRef)@"PGMidi MIDI Client", PGMIDINotifyProc, (__bridge void*)self, &client);
        NSLogError(s, @"Create MIDI client");

        s = MIDIOutputPortCreate(client, (CFStringRef)@"PGMidi Output Port", &outputPort);
        NSLogError(s, @"Create output MIDI port");

        s = MIDIInputPortCreate(client, (CFStringRef)@"PGMidi Input Port", PGMIDIReadProc, (__bridge void*)self, &inputPort);
        NSLogError(s, @"Create input MIDI port");

        [self scanExistingDevices];
        
        self.rescanTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(scanExistingDevices) userInfo:nil repeats:YES];
    }

    return self;
}

- (void) dealloc
{
    [_rescanTimer invalidate];
    self.rescanTimer = nil;
    
    if (outputPort)
    {
        OSStatus s = MIDIPortDispose(outputPort);
        NSLogError(s, @"Dispose MIDI port");
    }

    if (inputPort)
    {
        OSStatus s = MIDIPortDispose(inputPort);
        NSLogError(s, @"Dispose MIDI port");
    }

    if (client)
    {
        OSStatus s = MIDIClientDispose(client);
        NSLogError(s, @"Dispose MIDI client");
    }
    
    self.virtualEndpointName = nil;
    self.virtualSourceEnabled = NO;
    self.virtualDestinationEnabled = NO;
}

- (NSUInteger) numberOfConnections
{
    return sources.count + destinations.count;
}

- (MIDIPortRef) outputPort
{
    return outputPort;
}

-(BOOL)networkEnabled
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    return [MIDINetworkSession defaultSession].enabled;
#else
    return NO;
#endif
}

-(void)setNetworkEnabled:(BOOL)networkEnabled
{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    MIDINetworkSession* session = [MIDINetworkSession defaultSession];
    session.enabled = networkEnabled;
    session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
#else
    NSLog(@"MIDINetworkSession not available on Mac OS X");
#endif
}

-(BOOL)virtualSourceEnabled
{
    return virtualSourceDestination != nil;
}

-(void)setVirtualSourceEnabled:(BOOL)virtualSourceEnabled
{
    if (virtualSourceEnabled == self.virtualSourceEnabled) return;
    
    if (virtualSourceEnabled)
    {
        OSStatus s = MIDISourceCreate(client, (__bridge CFStringRef)@"MidiMonitor Source", &virtualSourceEndpoint);
        NSLogError(s, @"Create MIDI virtual source");
        if (s) return;
        
        virtualSourceDestination = [[PGMidiVirtualSourceDestination alloc] initWithMidi:self endpoint:virtualSourceEndpoint];

        [delegate midi:self destinationAdded:virtualSourceDestination];
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiDestinationAddedNotification
                                                            object:self 
                                                          userInfo:@{PGMidiConnectionKey: virtualSourceDestination}];
        
    }
    else
    {
        [delegate midi:self destinationRemoved:virtualSourceDestination];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiDestinationRemovedNotification
                                                            object:self 
                                                          userInfo:@{PGMidiConnectionKey: virtualSourceDestination}];

        virtualSourceDestination = nil;
        OSStatus s = MIDIEndpointDispose(virtualSourceEndpoint);
        NSLogError(s, @"Dispose MIDI virtual source");
        virtualSourceEndpoint = 0;
    }
}

-(BOOL)virtualDestinationEnabled
{
    return virtualDestinationSource != nil;
}

-(void)setVirtualDestinationEnabled:(BOOL)virtualDestinationEnabled
{
    if (virtualDestinationEnabled == self.virtualDestinationEnabled) return;
    
    if (virtualDestinationEnabled)
    {
        OSStatus s = MIDIDestinationCreate(client, (__bridge CFStringRef)@"MidiMonitor Destination", PGMIDIVirtualDestinationReadProc, (__bridge void*)self, &virtualDestinationEndpoint);
        NSLogError(s, @"Create MIDI virtual destination");
        if (s) return;
        
        // Attempt to use saved unique ID
        SInt32 uniqueID = (SInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"PGMIDI Saved Virtual Destination ID"];
        if (uniqueID)
        {
            s = MIDIObjectSetIntegerProperty(virtualDestinationEndpoint, kMIDIPropertyUniqueID, uniqueID);
            if (s == kMIDIIDNotUnique)
            {
                uniqueID = 0;
            }
        }
        // Save the ID
        if (!uniqueID)
        {
            s = MIDIObjectGetIntegerProperty(virtualDestinationEndpoint, kMIDIPropertyUniqueID, &uniqueID);
            NSLogError(s, @"Get MIDI virtual destination ID");
            if (s == noErr)
            {
                [[NSUserDefaults standardUserDefaults] setInteger:uniqueID forKey:@"PGMIDI Saved Virtual Destination ID"];
            }
        }
        
        virtualDestinationSource = [[PGMidiSource alloc] initWithMidi:self endpoint:virtualDestinationEndpoint];

        [delegate midi:self sourceAdded:virtualDestinationSource];
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiSourceAddedNotification
                                                            object:self
                                                          userInfo:@{PGMidiConnectionKey: virtualDestinationSource}];
    }
    else
    {
        [delegate midi:self sourceRemoved:virtualDestinationSource];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiSourceRemovedNotification
                                                            object:self 
                                                          userInfo:@{PGMidiConnectionKey: virtualDestinationSource}];

        virtualDestinationSource = nil;
        OSStatus s = MIDIEndpointDispose(virtualDestinationEndpoint);
        NSLogError(s, @"Dispose MIDI virtual destination");
        virtualDestinationEnabled = NO;
    }
}


//==============================================================================
#pragma mark Connect/disconnect

- (PGMidiSource*) getSource:(MIDIEndpointRef)source
{
    for (PGMidiSource *s in sources)
    {
        if (s.endpoint == source) return s;
    }
    return nil;
}

- (PGMidiDestination*) getDestination:(MIDIEndpointRef)destination
{
    for (PGMidiDestination *d in destinations)
    {
        if (d.endpoint == destination) return d;
    }
    return nil;
}

- (void) connectSource:(MIDIEndpointRef)endpoint
{
    PGMidiSource *source = [[PGMidiSource alloc] initWithMidi:self endpoint:endpoint];
    [sources addObject:source];
    [delegate midi:self sourceAdded:source];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiSourceAddedNotification
                                                        object:self 
                                                      userInfo:@{PGMidiConnectionKey: source}];
    
    OSStatus s = MIDIPortConnectSource(inputPort, endpoint, &source);
    NSLogError(s, @"Connecting to MIDI source");
}

- (void) disconnectSource:(MIDIEndpointRef)endpoint
{
    PGMidiSource *source = [self getSource:endpoint];

    if (source)
    {
        OSStatus s = MIDIPortDisconnectSource(inputPort, endpoint);
        NSLogError(s, @"Disconnecting from MIDI source");
        [sources removeObject:source];
        
        [delegate midi:self sourceRemoved:source];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiSourceRemovedNotification
                                                            object:self 
                                                          userInfo:@{PGMidiConnectionKey: source}];
    }
}

- (void) connectDestination:(MIDIEndpointRef)endpoint
{
    PGMidiDestination *destination = [[PGMidiDestination alloc] initWithMidi:self endpoint:endpoint];
    [destinations addObject:destination];
    [delegate midi:self destinationAdded:destination];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiDestinationAddedNotification
                                                        object:self 
                                                      userInfo:@{PGMidiConnectionKey: destination}];
}

- (void) disconnectDestination:(MIDIEndpointRef)endpoint
{
    PGMidiDestination *destination = [self getDestination:endpoint];

    if (destination)
    {
        [destinations removeObject:destination];
        
        [delegate midi:self destinationRemoved:destination];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:PGMidiDestinationRemovedNotification
                                                            object:self 
                                                          userInfo:@{PGMidiConnectionKey: destination}];
    }
}

- (void) scanExistingDevices
{
    const ItemCount numberOfDestinations = MIDIGetNumberOfDestinations();
    const ItemCount numberOfSources      = MIDIGetNumberOfSources();

    NSMutableArray *removedSources       = [NSMutableArray arrayWithArray:sources];
    NSMutableArray *removedDestinations  = [NSMutableArray arrayWithArray:destinations];
    
    for (ItemCount index = 0; index < numberOfDestinations; ++index) 
    {
        MIDIEndpointRef endpoint = MIDIGetDestination(index);
        if (endpoint == virtualDestinationEndpoint) continue;
        
        BOOL matched = NO;
        for (PGMidiDestination *destination in destinations)
        {
            if (destination.endpoint == endpoint)
            {
                [removedDestinations removeObject:destination];
                matched = YES;
                break;
            }
        }
        if (matched) continue;
        
        [self connectDestination:endpoint];
    }
    for (ItemCount index = 0; index < numberOfSources; ++index)
    {
        MIDIEndpointRef endpoint = MIDIGetSource(index);
        if (endpoint == virtualSourceEndpoint) continue;
        
        BOOL matched = NO;
        for (PGMidiDestination *source in sources)
        {
            if (source.endpoint == endpoint)
            {
                [removedSources removeObject:source];
                matched = YES;
                break;
            }
        }
        if (matched) continue;
        
        [self connectSource:endpoint];
    }
    
    for (PGMidiDestination *destination in removedDestinations)
    {
        [self disconnectDestination:destination.endpoint];
    }
    
    for (PGMidiSource *source in removedSources)
    {
        [self disconnectSource:source.endpoint];
    }
}

//==============================================================================
#pragma mark Notifications

- (void) midiNotifyAdd:(const MIDIObjectAddRemoveNotification *)notification
{
    if (notification->child == virtualDestinationEndpoint || notification->child == virtualSourceEndpoint) return;
    
    if (notification->childType == kMIDIObjectType_Destination)
        [self connectDestination:(MIDIEndpointRef)notification->child];
    else if (notification->childType == kMIDIObjectType_Source)
        [self connectSource:(MIDIEndpointRef)notification->child];
}

- (void) midiNotifyRemove:(const MIDIObjectAddRemoveNotification *)notification
{
    if (notification->child == virtualDestinationEndpoint || notification->child == virtualSourceEndpoint) return;
    
    if (notification->childType == kMIDIObjectType_Destination)
        [self disconnectDestination:(MIDIEndpointRef)notification->child];
    else if (notification->childType == kMIDIObjectType_Source)
        [self disconnectSource:(MIDIEndpointRef)notification->child];
}

- (void) midiNotify:(const MIDINotification*)notification
{
    switch (notification->messageID)
    {
        case kMIDIMsgObjectAdded:
            [self midiNotifyAdd:(const MIDIObjectAddRemoveNotification *)notification];
            break;
        case kMIDIMsgObjectRemoved:
            [self midiNotifyRemove:(const MIDIObjectAddRemoveNotification *)notification];
            break;
        case kMIDIMsgSetupChanged:
        case kMIDIMsgPropertyChanged:
        case kMIDIMsgThruConnectionsChanged:
        case kMIDIMsgSerialPortOwnerChanged:
        case kMIDIMsgIOError:
            break;
    }
}

void PGMIDINotifyProc(const MIDINotification *message, void *refCon)
{
    PGMidi *self = (__bridge PGMidi *)refCon;
    [self midiNotify:message];
}

//==============================================================================
#pragma mark MIDI Output

- (void) sendPacketList:(const MIDIPacketList *)packetList
{
    for (ItemCount index = 0; index < MIDIGetNumberOfDestinations(); ++index)
    {
        MIDIEndpointRef outputEndpoint = MIDIGetDestination(index);
        if (outputEndpoint)
        {
            // Send it
            OSStatus s = MIDISend(outputPort, outputEndpoint, packetList);
            NSLogError(s, @"Sending MIDI");
        }
    }
}

- (void) sendBytes:(const UInt8*)data size:(UInt32)size
{
    NSLog(@"%s(%u bytes to core MIDI)", __func__, size);
    assert(size < 65536);
    Byte packetBuffer[size+100];
    MIDIPacketList *packetList = (MIDIPacketList*)packetBuffer;
    MIDIPacket     *packet     = MIDIPacketListInit(packetList);

    packet = MIDIPacketListAdd(packetList, sizeof(packetBuffer), packet, 0, size, data);

    [self sendPacketList:packetList];
}

@end
