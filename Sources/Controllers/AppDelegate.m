//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import "AppDelegate.h"
#import "SystemVolume.h"
#import "AccessibilityDialog.h"

#import <IOKit/hidsystem/ev_keymap.h>

#import "OSD.h"

//This will handle signals for us, specifically SIGTERM.
void handleSIGTERM(int sig) {
    [NSApp terminate:nil];
}

#define USE_APPLE_CMD_MODIFIER_MENU_ID 3
#define LOCK_SYSTEM_AND_PLAYER_VOLUME_ID 9
#define START_AT_LOGIN_ID 4
#define AUTOMATIC_UPDATES_ID 8
#define PLAY_SOUND_FEEDBACK_ID 7
#define TAPPING_ID 1
#define HIDE_FROM_STATUS_BAR_ID 5
#define HIDE_VOLUME_WINDOW_ID 6

#pragma mark - Tapping key stroke events

//static void displayPreferencesChanged(CGDirectDisplayID displayID, CGDisplayChangeSummaryFlags flags, void *userInfo) {
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"displayResolutionHasChanged" object:NULL];
//}

CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    static int previousKeyCode = 0;
    static bool muteDown = false;
    NSEvent * sysEvent;
    
    if (type == kCGEventTapDisabledByTimeout) {
        //        NSLog(@"Event Taps Disabled! Re-enabling");
        [(__bridge AppDelegate *)(refcon) resetEventTap];
        return event;
    }
    
    // No event we care for, then return ASAP
    if (type != NX_SYSDEFINED) return event;
    
    sysEvent = [NSEvent eventWithCGEvent:event];
    // No need to test event type, we know it is NSSystemDefined, becuase that is the same as NX_SYSDEFINED
    // if ([sysEvent subtype] != NX_SUBTYPE_AUX_CONTROL_BUTTONS && [sysEvent subtype] != NX_SUBTYPE_AUX_MOUSE_BUTTONS) return event;
    if ([sysEvent subtype] != NX_SUBTYPE_AUX_CONTROL_BUTTONS) return event;
    
    AppDelegate* app=(__bridge AppDelegate *)(refcon);
    
    int keyFlags = ([sysEvent data1] & 0x0000FFFF);
    int keyCode = (([sysEvent data1] & 0xFFFF0000) >> 16);
    int keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    bool keyIsRepeat = (keyFlags & 0x1);
    CGEventFlags keyModifier = [sysEvent modifierFlags]|0xFFFF;
    
    // store whether Apple CMD modifier has been pressed or not
    [app setAppleCMDModifierPressed:(keyModifier&NX_COMMANDMASK)==NX_COMMANDMASK];
    
    switch( keyCode )
    {
        case NX_KEYTYPE_MUTE:
            
            if(previousKeyCode!=keyCode && app->volumeRampTimer)
            {
                [app stopVolumeRampTimer];
            }
            previousKeyCode=keyCode;
            
            if( keyState == 1 )
            {
                muteDown = true;
                [[NSNotificationCenter defaultCenter] postNotificationName:@"MuteVol" object:NULL];
            }
            else
            {
                muteDown = false;
            }
            return NULL;
            break;
        case NX_KEYTYPE_SOUND_UP:
        case NX_KEYTYPE_SOUND_DOWN:
            
            if(!muteDown)
            {
                if(previousKeyCode!=keyCode && app->volumeRampTimer)
                {
                    [app stopVolumeRampTimer];
                }
                previousKeyCode=keyCode;
                
                if( keyState == 1 )
                {
                    if( !app->volumeRampTimer )
                    {
                        if( keyCode == NX_KEYTYPE_SOUND_UP )
                            [[NSNotificationCenter defaultCenter] postNotificationName:(keyIsRepeat?@"IncVolRamp":@"IncVol") object:NULL];
                        else
                            [[NSNotificationCenter defaultCenter] postNotificationName:(keyIsRepeat?@"DecVolRamp":@"DecVol") object:NULL];
                    }
                }
                else
                {
                    if(app->volumeRampTimer)
                    {
                        [app stopVolumeRampTimer];
                    }
                }
                return NULL;
            }
            break;
    }
    
    
    return event;
}

#pragma mark - Class extension for status menu

@interface AppDelegate () <NSMenuDelegate>
{
    //StatusItemView* _statusBarItemView;
    NSTimer* _statusBarHideTimer;
    NSPopover* _hideFromStatusBarHintPopover;
    NSTextField* _hideFromStatusBarHintLabel;
    NSTimer *_hideFromStatusBarHintPopoverUpdateTimer;
    
    NSView* _hintView;
    NSViewController* _hintVC;
}

@end

#pragma mark - Extention music applications

@implementation PlayerApplication

@synthesize currentVolume = _currentVolume;

- (void) setCurrentVolume:(double)currentVolume
{
    [self setDoubleVolume:currentVolume];
    
    [musicPlayer setSoundVolume:round(currentVolume)];
}

- (double) currentVolume
{
    double vol = [musicPlayer soundVolume];
    
    if (fabs(vol-[self doubleVolume])<1)
    {
        vol = [self doubleVolume];
    }
    
    return vol;
}

- (void) nextTrack
{
    return [musicPlayer nextTrack];
}

- (void) previousTrack
{
    return [musicPlayer previousTrack];
}

- (void) playPause
{
    return [musicPlayer playPause];
}

- (BOOL) isRunning
{
    return [musicPlayer isRunning];
}

- (iTunesEPlS) playerState
{
    return [musicPlayer playerState];
}

-(id)initWithBundleIdentifier:(NSString*) bundleIdentifier {
    if (self = [super init])  {
        [self setCurrentVolume: -100];
        [self setOldVolume: -1];
        musicPlayer = [SBApplication applicationWithBundleIdentifier:bundleIdentifier];
        
    }
    return self;
}

@end

#pragma mark - Implementation AppDelegate

@implementation AppDelegate

// @synthesize AppleRemoteConnected=_AppleRemoteConnected;
@synthesize StartAtLogin=_StartAtLogin;
@synthesize Tapping=_Tapping;
@synthesize UseAppleCMDModifier=_UseAppleCMDModifier;
@synthesize LockSystemAndPlayerVolume=_LockSystemAndPlayerVolume;
@synthesize AppleCMDModifierPressed=_AppleCMDModifierPressed;
@synthesize AutomaticUpdates=_AutomaticUpdates;
@synthesize hideFromStatusBar = _hideFromStatusBar;
@synthesize hideVolumeWindow = _hideVolumeWindow;
@synthesize loadIntroAtStart = _loadIntroAtStart;
@synthesize statusBar = _statusBar;

@synthesize iTunesBtn = _iTunesBtn;
@synthesize spotifyBtn = _spotifyBtn;
@synthesize systemBtn = _systemBtn;
@synthesize dopplerBtn = _dopplerBtn;

@synthesize iTunesPerc = _iTunesPerc;
@synthesize spotifyPerc = _spotifyPerc;
@synthesize systemPerc = _systemPerc;
@synthesize dopplerPerc = _dopplerPerc;

@synthesize sparkle_updater = _sparkle_updater;

@synthesize statusMenu = _statusMenu;

static NSTimeInterval volumeRampTimeInterval=0.01f;
static NSTimeInterval statusBarHideDelay=10.0f;
static NSTimeInterval checkPlayerTimeout=0.3f;
static NSTimeInterval volumeLockSyncInterval=1.0f;
static NSTimeInterval updateSystemVolumeInterval=0.1f;

- (IBAction)terminate:(id)sender
{
    if(CFMachPortIsValid(eventTap)) {
        CFMachPortInvalidate(eventTap);
        CFRunLoopSourceInvalidate(runLoopSource);
        CFRelease(eventTap);
        CFRelease(runLoopSource);
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    
    systemAudio = nil;
    iTunes = nil;
    spotify = nil;
    doppler = nil;
    
    _statusBar = nil;
    
    accessibilityDialog = nil;
    introWindowController = nil;
    
    [volumeRampTimer invalidate];
    volumeRampTimer = nil;
    
    [checkPlayerTimer invalidate];
    checkPlayerTimer = nil;
    
    [timerImgSpeaker invalidate];
    timerImgSpeaker = nil;
    
    [updateSystemVolumeTimer invalidate];
    updateSystemVolumeTimer = nil;
     
    preferences = nil;
    
    [NSApp terminate:nil];
}

- (bool) StartAtLogin
{
    NSURL *appURL=[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    
    bool found=false;
    
    if (loginItems) {
        UInt32 seedValue;
        //Retrieve the list of Login Items and cast them to a NSArray so that it will be easier to iterate.
        NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
        
        for(int i=0; i<[loginItemsArray count]; i++)
        {
            LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
            //Resolve the item with URL
            CFURLRef url = NULL;
            
            // LSSharedFileListItemResolve is deprecated in Mac OS X 10.10
            // Switch to LSSharedFileListItemCopyResolvedURL if possible
#if MAC_OS_X_VERSION_MIN_REQUIRED < 101000 // MAC_OS_X_VERSION_10_10
            LSSharedFileListItemResolve(itemRef, 0, &url, NULL);
#else
            url = LSSharedFileListItemCopyResolvedURL(itemRef, 0, NULL);
#endif
            
            if ( url ) {
                if ( CFEqual(url, (__bridge CFTypeRef)(appURL)) ) // found it
                {
                    found=true;
                }
                CFRelease(url);
            }
            
            if(found)break;
        }
        
        CFRelease((__bridge CFTypeRef)(loginItemsArray));
        CFRelease(loginItems);
    }
    
    return found;
}

- (void)wasAuthorized
{
    [accessibilityDialog close];
    accessibilityDialog = nil;
    
    [self completeInitialization];
}

- (void)setStartAtLogin:(bool)enabled savePreferences:(bool)savePreferences
{
    NSMenuItem* menuItem=[_statusMenu itemWithTag:START_AT_LOGIN_ID];
    [menuItem setState:enabled];
    
    if(savePreferences)
    {
        NSURL *appURL=[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
        
        LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        
        if (loginItems) {
            if(enabled)
            {
                // Insert the item at the bottom of Login Items list.
                LSSharedFileListItemRef loginItemRef = LSSharedFileListInsertItemURL(loginItems,
                                                                                     kLSSharedFileListItemLast,
                                                                                     NULL,
                                                                                     NULL,
                                                                                     (__bridge CFURLRef)appURL,
                                                                                     NULL,
                                                                                     NULL);
                if (loginItemRef) {
                    CFRelease(loginItemRef);
                }
            }
            else
            {
                UInt32 seedValue;
                //Retrieve the list of Login Items and cast them to a NSArray so that it will be easier to iterate.
                NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
                for(int i=0; i<[loginItemsArray count]; i++)
                {
                    LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
                    //Resolve the item with URL
                    CFURLRef URL = NULL;
                    
                    // LSSharedFileListItemResolve is deprecated in Mac OS X 10.10
                    // Switch to LSSharedFileListItemCopyResolvedURL if possible
#if MAC_OS_X_VERSION_MIN_REQUIRED < 101000 // MAC_OS_X_VERSION_10_10
                    LSSharedFileListItemResolve(itemRef, 0, &URL, NULL);
#else
                    URL = LSSharedFileListItemCopyResolvedURL(itemRef, 0, NULL);
#endif
                    
                    if ( URL ) {
                        if ( CFEqual(URL, (__bridge CFTypeRef)(appURL)) ) // found it
                        {
                            LSSharedFileListItemRemove(loginItems,itemRef);
                        }
                        CFRelease(URL);
                    }
                }
                CFRelease((__bridge CFTypeRef)(loginItemsArray));
            }
            CFRelease(loginItems);
        }
    }
}

- (void)stopVolumeRampTimer
{
    [volumeRampTimer invalidate];
    volumeRampTimer=nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SoundFeedback" object:NULL];
    
    checkPlayerTimer = [NSTimer timerWithTimeInterval:checkPlayerTimeout target:self selector:@selector(resetCurrentPlayer:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:checkPlayerTimer forMode:NSRunLoopCommonModes];
}

- (void)rampVolumeUp:(NSTimer*)theTimer
{
    [self setVolumeUp:true];
}

- (void)rampVolumeDown:(NSTimer*)theTimer
{
    [self setVolumeUp:false];
}

- (bool)createEventTap
{
    if(eventTap != nil && CFMachPortIsValid(eventTap)) {
        CFMachPortInvalidate(eventTap);
        CFRunLoopSourceInvalidate(runLoopSource);
        CFRelease(eventTap);
        CFRelease(runLoopSource);
    }
    
    CGEventMask eventMask = (/*(1 << kCGEventKeyDown) | (1 << kCGEventKeyUp) |*/CGEventMaskBit(NX_SYSDEFINED));
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                eventMask, event_tap_callback, (__bridge void *)self); // Create an event tap. We are interested in SYS key presses.
    
    if(eventTap != nil)
    {
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0); // Create a run loop source.
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes); // Add to the current run loop.
        return true;
    }
    else
        return false;
}

-(void) sendMediaKey: (int)key {
    // create and send down key event
    NSEvent* key_event;
    
    key_event = [NSEvent otherEventWithType:NSEventTypeSystemDefined location:CGPointZero modifierFlags:0xa00 timestamp:0 windowNumber:0 context:0 subtype:8 data1:((key << 16) | (0xa << 8)) data2:-1];
    CGEventPost(0, key_event.CGEvent);
    // NSLog(@"%d keycode (down) sent",key);
    
    // create and send up key event
    key_event = [NSEvent otherEventWithType:NSEventTypeSystemDefined location:CGPointZero modifierFlags:0xb00 timestamp:0 windowNumber:0 context:0 subtype:8 data1:((key << 16) | (0xb << 8)) data2:-1];
    CGEventPost(0, key_event.CGEvent);
    // NSLog(@"%d keycode (up) sent",key);
}

- (void)PlayPauseMusic:(NSNotification *)aNotification
{
    [self sendMediaKey:NX_KEYTYPE_PLAY];
}

- (void)NextTrackMusic:(NSNotification *)aNotification
{
    [self sendMediaKey:NX_KEYTYPE_NEXT];
}

- (void)PreviousTrackMusic:(NSNotification *)aNotification
{
    [self sendMediaKey:NX_KEYTYPE_PREVIOUS];
}

- (void)MuteVol:(NSNotification *)aNotification
{
    id runningPlayerPtr = [self runningPlayer];
    
    if (runningPlayerPtr != nil)
    {
        if([runningPlayerPtr oldVolume]<0)
        {
            [runningPlayerPtr setOldVolume:[runningPlayerPtr currentVolume]];
            [runningPlayerPtr setCurrentVolume:0];
            
            if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
                [systemAudio setOldVolume:[systemAudio currentVolume]];
                [systemAudio setCurrentVolume:0];
            }
            
            if(!_hideVolumeWindow)
                [[self->OSDManager sharedManager] showImage:OSDGraphicSpeakerMute onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:0 totalChiclets:(unsigned int)100 locked:NO];
            
        }
        else
        {
            [runningPlayerPtr setCurrentVolume:[runningPlayerPtr oldVolume]];
            
            if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
                [systemAudio setCurrentVolume:[systemAudio oldVolume]];
            }
            
            if(!_hideVolumeWindow)
                [[self->OSDManager sharedManager] showImage:OSDGraphicSpeaker onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:(unsigned int)[runningPlayerPtr oldVolume] totalChiclets:(unsigned int)100 locked:NO];
            
            [runningPlayerPtr setOldVolume:-1];
        }
        
        if (runningPlayerPtr == iTunes)
            [self setItunesVolume:[runningPlayerPtr currentVolume]];
        else if (runningPlayerPtr == spotify)
            [self setSpotifyVolume:[runningPlayerPtr currentVolume]];
        else if (runningPlayerPtr == doppler)
            [self setSpotifyVolume:[runningPlayerPtr currentVolume]];
        
        if (_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio)
            [self setSystemVolume:[runningPlayerPtr currentVolume]];
    }
}

- (void)IncVol:(NSNotification *)aNotification
{
    if( [[aNotification name] isEqualToString:@"IncVolRamp"] )
    {
        [checkPlayerTimer invalidate];
        checkPlayerTimer = nil;
        volumeRampTimer=[NSTimer timerWithTimeInterval:volumeRampTimeInterval*(NSTimeInterval)increment target:self selector:@selector(rampVolumeUp:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:volumeRampTimer forMode:NSRunLoopCommonModes];
        
        if(timerImgSpeaker) {[timerImgSpeaker invalidate]; timerImgSpeaker=nil;}
    }
    else
    {
        [self setVolumeUp:true];
    }
}

- (void)DecVol:(NSNotification *)aNotification
{
    if( [[aNotification name] isEqualToString:@"DecVolRamp"] )
    {
        [checkPlayerTimer invalidate];
        checkPlayerTimer = nil;
        volumeRampTimer=[NSTimer timerWithTimeInterval:volumeRampTimeInterval*(NSTimeInterval)increment target:self selector:@selector(rampVolumeDown:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:volumeRampTimer forMode:NSRunLoopCommonModes];
        
        if(timerImgSpeaker) {[timerImgSpeaker invalidate]; timerImgSpeaker=nil;}
    }
    else
    {
        [self setVolumeUp:false];
    }
}

- (id)init
{
    self = [super init];
    if(self)
    {
        self->eventTap = nil;
                
        if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6) {
            //10.6.x or earlier systems
            osxVersion = 106;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_7) {
            /* On a 10.7 - 10.7.x system */
            osxVersion = 107;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_8) {
            /* On a 10.8 - 10.8.x system */
            osxVersion = 108;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_9) {
            /* On a 10.9 - 10.9.x system */
            osxVersion = 109;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_10) {
            /* On a 10.10 - 10.10.x system */
            osxVersion = 110;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_11) {
            /* On a 10.11 - 10.11.x system */
            osxVersion = 111;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_12) {
            /* On a 10.12 - 10.12.x system */
            osxVersion = 112;
        } else if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_13) {
            /* On a 10.13 - 10.13.x system */
            osxVersion = 113;
        } else if (floor(NSAppKitVersionNumber) <= 1671) {
            /* On a 10.14 - 10.14.x system */
            osxVersion = 114;
        }
        else if (floor(NSAppKitVersionNumber) <= 1894) {
            /* On a 10.15 - 10.15.x system */
            osxVersion = 115;
        }
        else
        {
            osxVersion = 115;
        }
        
        menuIsVisible=false;
        currentPlayer=nil;
        
        updateSystemVolumeTimer=nil;
        volumeRampTimer=nil;
        timerImgSpeaker=nil;
        checkPlayerTimer=nil;
        
    }
    return self;
}


-(void)awakeFromNib
{
}

-(void)completeInitialization
{
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    //NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    //NSString * operatingSystemVersionString = [[NSProcessInfo processInfo] operatingSystemVersionString];
    NSString* releasesCast = [infoDict objectForKey:@"ReleasesCast"];
    
    SPUUpdater* updater = [[self sparkle_updater] updater];
    [updater setFeedURL:[NSURL URLWithString:releasesCast]];
    [updater setUpdateCheckInterval:60*60*24*7]; // look for new updates every 7 days
    
    //[[SUUpdater sharedUpdater] setFeedURL:[NSURL URLWithString:[NSString stringWithFormat: @"http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/VolumeControlCast.xml.php?version=%@&osxversion=%@",version,[operatingSystemVersionString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]]]];
    //[[SUUpdater sharedUpdater] setUpdateCheckInterval:60*60*24*7]; // look for new updates every 7 days
    
    // [self _loadBezelServices]; // El Capitan and probably older systems
    [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"] load];
    self->OSDManager = NSClassFromString(@"OSDManager");
    
    //[self checkSIPforAppIdentifier:@"com.apple.iTunes" promptIfNeeded:YES];
    //[self checkSIPforAppIdentifier:@"com.spotify.client" promptIfNeeded:YES];
    
    if(osxVersion >= 115)
        iTunes = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.apple.Music"];
    else
        iTunes = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.apple.iTunes"];
    
    spotify = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.spotify.client"];

    doppler = [[PlayerApplication alloc] initWithBundleIdentifier:@"co.brushedtype.doppler-macos"];
    
    // Force MacOS to ask for authorization to AppleEvents if this was not already given
    if([iTunes isRunning])
        [iTunes currentVolume];
    if([spotify isRunning])
        [spotify currentVolume];
    if([doppler isRunning])
        [doppler currentVolume];
    
    systemAudio = [[SystemApplication alloc] initWithVersion:osxVersion];
    
    [self showInStatusBar];   // Install icon into the menu bar
    
    // NSString* iTunesVersion = [[NSString alloc] initWithString:[iTunes version]];
    // NSString* spotifyVersion = [[NSString alloc] initWithString:[spotify version]];
    
    [self initializePreferences];
    
    [self setStartAtLogin:[self StartAtLogin] savePreferences:false];
    
    volumeSound = [[NSSound alloc] initWithContentsOfFile:@"/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff" byReference:false];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    //    if (menuItem.tag == USE_APPLE_CMD_MODIFIER_MENU_ID) { // CMD Modifier menu item
    //        return ![self LockSystemAndPlayerVolume]; // Disable when locked
    //    }
    return YES; // Default behavior
}

- (void)emitAcousticFeedback:(NSNotification *)aNotification
{
    if([self PlaySoundFeedback] && (_AppleCMDModifierPressed != _UseAppleCMDModifier || [[self runningPlayer] isKindOfClass:[SystemApplication class]]))
    {
        if([volumeSound isPlaying])
            [volumeSound stop];
        [volumeSound play];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emitAcousticFeedback:) name:@"SoundFeedback" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(IncVol:) name:@"IncVol" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(IncVol:) name:@"IncVolRamp" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(DecVol:) name:@"DecVol" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(DecVol:) name:@"DecVolRamp" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(MuteVol:) name:@"MuteVol" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PlayPauseMusic:) name:@"PlayPauseMusic" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(NextTrackMusic:) name:@"NextTrackMusic" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(PreviousTrackMusic:) name:@"PreviousTrackMusic" object:nil];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self selector: @selector(receiveWakeNote:) name:NSWorkspaceDidWakeNotification object: NULL];
    
    signal(SIGTERM, handleSIGTERM);
    
    extern CFStringRef kAXTrustedCheckOptionPrompt __attribute__((weak_import));
        
    if( AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @NO}) && [self createEventTap] )
    {
        [self completeInitialization];
    }
    else
    {
        accessibilityDialog = [[AccessibilityDialog alloc] initWithWindowNibName:@"AccessibilityDialog"];
        
        [accessibilityDialog showWindow:self];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    [self showInStatusBar];
    [self setHideFromStatusBar:[self hideFromStatusBar]];
    if ([self hideFromStatusBar])
    {
        [self showHideFromStatusBarHintPopover];
    }
    
    return false;
}

- (void)showInStatusBar
{
    if (![self statusBar])
    {
        // the status bar item needs a custom view so that we can show a NSPopover for the hide-from-status-bar hint
        // the view now reacts to the mouseDown event to show the menu
        
        _statusBar =  [[NSStatusBar systemStatusBar] statusItemWithLength:15];
        [[self statusBar] setMenu:[self statusMenu]];
    }
        
    NSImage* icon = [NSImage imageNamed:@"statusbar-icon"];
    [icon setTemplate:YES];
        
    NSStatusBarButton *statusBarButton = [[self statusBar] button];
    [statusBarButton setImage:icon];
    [statusBarButton setAppearsDisabled:false];
    
}

- (void)updateSystemVolume:(NSTimer*)theTimer
{
    if([systemAudio isMuted])
        [[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",0]];
    else
        [[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)[systemAudio currentVolume]]];
}

- (void)initializePreferences
{
    preferences = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInt:2],      @"volumeIncrement",
                          [NSNumber numberWithBool:true] , @"TappingEnabled",
                          [NSNumber numberWithBool:false], @"UseAppleCMDModifier",
                          [NSNumber numberWithBool:false], @"LockSystemAndPlayerVolume",
                          [NSNumber numberWithBool:true],  @"AutomaticUpdates",
                          [NSNumber numberWithBool:false], @"hideFromStatusBarPreference",
                          [NSNumber numberWithBool:false], @"hideVolumeWindowPreference",
                          [NSNumber numberWithBool:true],  @"iTunesControl",
                          [NSNumber numberWithBool:true],  @"spotifyControl",
                          [NSNumber numberWithBool:true],  @"dopplerControl",
                          [NSNumber numberWithBool:true],  @"systemControl",
                          [NSNumber numberWithBool:true],  @"PlaySoundFeedback",
                          nil ]; // terminate the list
    [preferences registerDefaults:dict];
    
    [self setTapping:[preferences boolForKey:              @"TappingEnabled"]];
    [self setUseAppleCMDModifier:[preferences boolForKey:  @"UseAppleCMDModifier"]];
    [self setLockSystemAndPlayerVolume:[preferences boolForKey:  @"LockSystemAndPlayerVolume"]];
    [self setAutomaticUpdates:[preferences boolForKey:     @"AutomaticUpdates"]];
    [self setHideFromStatusBar:[preferences boolForKey:    @"hideFromStatusBarPreference"]];
    [self setHideVolumeWindow:[preferences boolForKey:     @"hideVolumeWindowPreference"]];
    [[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
    if(osxVersion >= 115)
    {
        [[self iTunesBtn] setTitle:@"Music"];
    }
    [[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
    [[self spotifyBtn] setState:[preferences boolForKey:   @"spotifyControl"]];
    [[self dopplerBtn] setState:[preferences boolForKey:   @"dopplerControl"]];
    //[[self systemBtn] setState:[preferences boolForKey:    @"systemControl"]];
    [[self systemBtn] setState:true];  // hard coded always to true
    [[self systemBtn] setEnabled:false];
    [self setPlaySoundFeedback:[preferences boolForKey:     @"PlaySoundFeedback"]];
    
    NSInteger volumeIncSetting = [preferences integerForKey:@"volumeIncrement"];
    [self setVolumeInc:volumeIncSetting];
    
    [[self volumeIncrementsSlider] setIntegerValue: volumeIncSetting];
}

- (IBAction)toggleAutomaticUpdates:(id)sender
{
    [self setAutomaticUpdates:![self AutomaticUpdates]];
}

- (void) setAutomaticUpdates:(bool)enabled
{
    NSMenuItem* menuItem=[_statusMenu itemWithTag:AUTOMATIC_UPDATES_ID];
    [menuItem setState:enabled];
    
    [preferences setBool:enabled forKey:@"AutomaticUpdates"];
    [preferences synchronize];
    
    _AutomaticUpdates=enabled;
    
    [[SUUpdater sharedUpdater] setAutomaticallyChecksForUpdates:enabled];
}

- (IBAction)togglePlaySoundFeedback:(id)sender
{
    [self setPlaySoundFeedback:![self PlaySoundFeedback]];
}

- (void)setPlaySoundFeedback:(bool)enabled
{
    [preferences setBool:enabled forKey:@"PlaySoundFeedback"];
    [preferences synchronize];
    
    NSMenuItem* menuItem=[_statusMenu itemWithTag:PLAY_SOUND_FEEDBACK_ID];
    [menuItem setState:enabled];
        
    _PlaySoundFeedback=enabled;
}

- (IBAction)toggleStartAtLogin:(id)sender
{
    [self setStartAtLogin:![self StartAtLogin] savePreferences:true];
}

- (void) setUseAppleCMDModifier:(bool)enabled
{
    NSMenuItem* menuItem=[_statusMenu itemWithTag:USE_APPLE_CMD_MODIFIER_MENU_ID];
    [menuItem setState:enabled];
    
    [preferences setBool:enabled forKey:@"UseAppleCMDModifier"];
    [preferences synchronize];
    
    _UseAppleCMDModifier=enabled;
}

- (IBAction)toggleUseAppleCMDModifier:(id)sender
{
    [self setUseAppleCMDModifier:![self UseAppleCMDModifier]];
}

- (IBAction)toggleLockSystemAndPlayerVolume:(id)sender
{
    NSMenuItem* CMDModifierMenuItem=[_statusMenu itemWithTag:USE_APPLE_CMD_MODIFIER_MENU_ID];
    
    [self setLockSystemAndPlayerVolume:![self LockSystemAndPlayerVolume]];
}

/*
- (void) syncSystemVolume:(NSTimer*)theTimer
{
    id runningPlayerPtr = [self runningPlayer];
    
    if (runningPlayerPtr != nil && runningPlayerPtr != systemAudio)
    {
        double systemVolume = [systemAudio currentVolume];
        double volume = [runningPlayerPtr currentVolume];
        double diff = systemVolume - volume;
        if (diff<0) diff = -diff;
        if( diff>1E-3 ) {
            NSLog(@"EQUALIZING");
            NSLog(@"Player volume: %1.5f",volume);
            NSLog(@"Apple Music: %d",runningPlayerPtr == iTunes);
            NSLog(@"System volume: %1.5f",systemVolume);
            NSLog(@"Diff: %1.10f",diff);
            [systemAudio setCurrentVolume:volume];
            [self setSystemVolume:volume];
        }
    }
}
*/

- (void) setLockSystemAndPlayerVolume:(bool)enabled
{
    NSMenuItem* menuItem=[_statusMenu itemWithTag:LOCK_SYSTEM_AND_PLAYER_VOLUME_ID];
    [menuItem setState:enabled];

    [preferences setBool:enabled forKey:@"LockSystemAndPlayerVolume"];
    [preferences synchronize];

    _LockSystemAndPlayerVolume=enabled;
    
    /*
    if(_LockSystemAndPlayerVolume) {
        volumeLockSyncTimer = [NSTimer timerWithTimeInterval:volumeLockSyncInterval target:self selector:@selector(syncSystemVolume:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:volumeLockSyncTimer forMode:NSRunLoopCommonModes];
    } else {
        [volumeLockSyncTimer invalidate];
        volumeLockSyncTimer = nil;
    }
    */
}

- (void) setTapping:(bool)enabled
{
    NSMenuItem* menuItem=[_statusMenu itemWithTag:TAPPING_ID];
    [menuItem setState:enabled];
    
    CGEventTapEnable(eventTap, enabled);
    
    [[[self statusBar] button] setAppearsDisabled:!enabled];
    
    [preferences setBool:enabled forKey:@"TappingEnabled"];
    [preferences synchronize];
    
    _Tapping=enabled;
}

- (IBAction)toggleTapping:(id)sender
{
    [self setTapping:![self Tapping]];
}

- (IBAction)sliderValueChanged:(NSSliderCell*)slider
{
    NSInteger volumeIncSetting = [[self volumeIncrementsSlider] integerValue];
    
    [self setVolumeInc:volumeIncSetting];
    
    [preferences setInteger:volumeIncSetting forKey:@"volumeIncrement"];
    [preferences synchronize];
    
}

- (void) setVolumeInc:(NSInteger)volumeIncSetting
{
    switch(volumeIncSetting)
    {
        case 5:
            increment = 25;
            break;
        case 4:
            increment = 12.5;
            break;
        case 3:
            increment = 6.25;
            break;
        case 2:
            increment = 3.125;
            break;
        case 1:
        default:
            increment = 1.5625;
            break;
            
    }
}

- (IBAction)aboutPanel:(id)sender
{
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleVersion"];
    NSRange range=[version rangeOfString:@"." options:NSBackwardsSearch];
    if(version>0) version=[version substringFromIndex:range.location+1];
    
    infoDict = [NSDictionary dictionaryWithObjectsAndKeys:
                version,@"Version",
                nil ]; // terminate the list
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:infoDict];
}

- (void) receiveWakeNote: (NSNotification*) note
{
    NSLog(@"Received WakeNote: %@", [note name]);
    [self setTapping:[self Tapping]];
}

- (void) dealloc
{
    
}

-(void)resetEventTap
{
    CGEventTapEnable(eventTap, _Tapping);
}

- (void)resetCurrentPlayer:(NSTimer*)theTimer
{
    // Keep memory of the current player until this timeout is reached
    // After the timeout, it is forced to check again what the current player is
    [checkPlayerTimer invalidate];
    checkPlayerTimer = nil;
    currentPlayer = nil;
}

- (id)runningPlayer
{
    if(currentPlayer)
        return currentPlayer;
    
    checkPlayerTimer = [NSTimer timerWithTimeInterval:checkPlayerTimeout target:self selector:@selector(resetCurrentPlayer:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:checkPlayerTimer forMode:NSRunLoopCommonModes];
    
    if(_AppleCMDModifierPressed == _UseAppleCMDModifier)
    {
        if([_iTunesBtn state] && [iTunes isRunning] && [iTunes playerState] == iTunesEPlSPlaying)
        {
            currentPlayer = iTunes;
        }
        else if([_spotifyBtn state] && [spotify isRunning] && [spotify playerState] == SpotifyEPlSPlaying)
        {
            currentPlayer = spotify;
        }
        else if([_dopplerBtn state] && [doppler isRunning] && [doppler playerState] == DopplerEPlSPlaying)
        {
            currentPlayer = doppler;
        }
        else if([_systemBtn state])
        {
            currentPlayer = systemAudio;
        }
    }
    else
        currentPlayer = systemAudio;
    
    return currentPlayer;
}

- (void)setVolumeUp:(bool)increase
{
    id runningPlayerPtr = [self runningPlayer];
    
    if (runningPlayerPtr != nil)
    {
        double volume = [runningPlayerPtr currentVolume];
        NSLog(@"Current volume: %1.2f%%", volume);
        
        if([runningPlayerPtr oldVolume]<0) // if it was not mute
        {
            //volume=[musicProgramPnt soundVolume]+_volumeInc*(increase?1:-1);
            volume += (increase?1:-1)*increment;
        }
        else // if it was mute
        {
            // [volumeImageLayer setContents:imgVolOn];  // restore the image of the speaker from mute speaker
            volume=[runningPlayerPtr oldVolume];
            [runningPlayerPtr setOldVolume:-1];  // this says that it is not mute
        }
        if (volume<0) volume=0;
        if (volume>100) volume=100;
        
        OSDGraphic image = (volume > 0)? OSDGraphicSpeaker : OSDGraphicSpeakerMute;
        
        NSInteger numFullBlks = floor(volume/6.25);
        NSInteger numQrtsBlks = round((volume-(double)numFullBlks*6.25)/1.5625);
        
        //NSLog(@"%d %d",(int)numFullBlks,(int)numQrtsBlks);
        
        if(!_hideVolumeWindow)
            [[self->OSDManager sharedManager] showImage:image onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:(unsigned int)(round(((numFullBlks*4+numQrtsBlks)*1.5625)*100)) totalChiclets:(unsigned int)10000 locked:NO];
        
        [runningPlayerPtr setCurrentVolume:volume];
        if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
            [systemAudio setCurrentVolume:volume];
        }
    
        if(self->volumeRampTimer == nil)
            [self emitAcousticFeedback:nil];
        
        if( runningPlayerPtr == iTunes)
            [self setItunesVolume:volume];
        else if( runningPlayerPtr == spotify)
            [self setSpotifyVolume:volume];
        else if (runningPlayerPtr == doppler)
            [self setDopplerVolume:volume];
        
        if(_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio)
            [self setSystemVolume:volume];
        
        [self refreshVolumeBar:(int)volume];
        
        NSLog(@"New volume: %1.2f%%", [runningPlayerPtr currentVolume]);
    }
}

- (void) setItunesVolume:(NSInteger)volume
{
    if (volume == -1)
        [[self iTunesPerc] setHidden:YES];
    else
    {
        [[self iTunesPerc] setHidden:NO];
        [[self iTunesPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
    }
}

- (void) setSpotifyVolume:(NSInteger)volume
{
    if (volume == -1)
        [[self spotifyPerc] setHidden:YES];
    else
    {
        [[self spotifyPerc] setHidden:NO];
        [[self spotifyPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
    }
}

- (void) setDopplerVolume:(NSInteger)volume
{
    if (volume == -1)
        [[self dopplerPerc] setHidden:YES];
    else
    {
        [[self dopplerPerc] setHidden:NO];
        [[self dopplerPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
    }
}

- (void) setSystemVolume:(NSInteger)volume
{
    if (volume == -1)
        [[self systemPerc] setHidden:YES];
    else
    {
        [[self systemPerc] setHidden:NO];
        [[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
    }
    
}

- (void) updatePercentages
{
    if([iTunes isRunning])
        [self setItunesVolume:[iTunes currentVolume]];
    else
        [self setItunesVolume:-1];
    
    if([spotify isRunning])
        [self setSpotifyVolume:[spotify currentVolume]];
    else
        [self setSpotifyVolume:-1];

    if ([doppler isRunning])
        [self setDopplerVolume:[doppler currentVolume]];
    else
        [self setDopplerVolume:-1];
    
    [self setSystemVolume:[systemAudio currentVolume]];
}

- (void) refreshVolumeBar:(NSInteger)volume
{
    NSInteger doubleFullRectangles = (NSInteger)round(32.0f * volume / 100.0f);
    NSInteger fullRectangles=doubleFullRectangles>>1;
    
    [CATransaction begin];
    [CATransaction setAnimationDuration: 0.0];
    [CATransaction setDisableActions: TRUE];
    
    if(volume==0)
    {
        [volumeImageLayer setContents:imgVolOff];
    }
    else
    {
        [volumeImageLayer setContents:imgVolOn];
    }
    
    CGRect frame;
    
    for(NSInteger i=0; i<fullRectangles; i++)
    {
        frame = [volumeBar[i] frame];
        frame.size.width=9;
        [volumeBar[i] setFrame:frame];
        
        [volumeBar[i] setHidden:NO];
    }
    for(NSInteger i=fullRectangles; i<16; i++)
    {
        frame = [volumeBar[i] frame];
        frame.size.width=9;
        [volumeBar[i] setFrame:frame];
        
        [volumeBar[i] setHidden:YES];
    }
    
    if(fullRectangles*2 != doubleFullRectangles)
    {
        
        frame = [volumeBar[fullRectangles] frame];
        frame.size.width=5;
        
        [volumeBar[fullRectangles] setFrame:frame];
        [volumeBar[fullRectangles] setHidden:NO];
    }
    
    [CATransaction commit];
}


#pragma mark - Hide From Status Bar

- (IBAction)toggleHideFromStatusBar:(id)sender
{
    [self setHideFromStatusBar:![self hideFromStatusBar]];
    if ([self hideFromStatusBar])
        [self showHideFromStatusBarHintPopover];
}

- (void)setHideFromStatusBar:(bool)enabled
{
    _hideFromStatusBar=enabled;
    
    NSMenuItem* menuItem=[_statusMenu itemWithTag:HIDE_FROM_STATUS_BAR_ID];
    [menuItem setState:[self hideFromStatusBar]];
    
    [preferences setBool:enabled forKey:@"hideFromStatusBarPreference"];
    [preferences synchronize];
    
    if(enabled)
    {
        if (![_statusBarHideTimer isValid] && [self statusBar])
        {
            [self setHideFromStatusBarHintLabelWithSeconds:statusBarHideDelay];
            _statusBarHideTimer = [NSTimer timerWithTimeInterval:statusBarHideDelay target:self selector:@selector(doHideFromStatusBar:) userInfo:nil repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:_statusBarHideTimer forMode:NSRunLoopCommonModes];
            _hideFromStatusBarHintPopoverUpdateTimer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(updateHideFromStatusBarHintPopover:) userInfo:nil repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:_hideFromStatusBarHintPopoverUpdateTimer forMode:NSRunLoopCommonModes];
        }
    }
    else
    {
        [_hideFromStatusBarHintPopover close];
        [_statusBarHideTimer invalidate];
        _statusBarHideTimer = nil;
        [_hideFromStatusBarHintPopoverUpdateTimer invalidate];
        _hideFromStatusBarHintPopoverUpdateTimer = nil;
    }
}

- (void)doHideFromStatusBar:(NSTimer*)aTimer
{
    [_hideFromStatusBarHintPopoverUpdateTimer invalidate];
    _hideFromStatusBarHintPopoverUpdateTimer = nil;
    _statusBarHideTimer = nil;
    [_hideFromStatusBarHintPopover close];
    [[NSStatusBar systemStatusBar] removeStatusItem:[self statusBar]];
    _statusBar = nil;
    
    [self setHideFromStatusBar:true];
}

- (void)showHideFromStatusBarHintPopover
{
    if ([_hideFromStatusBarHintPopover isShown]) return;
    
    if (! _hideFromStatusBarHintPopover)
    {
        CGRect popoverRect = (CGRect) {
            .size.width = 250,
            .size.height = 63
        };
        
        _hideFromStatusBarHintLabel = [[NSTextField alloc] initWithFrame:CGRectInset(popoverRect, 10, 10)];
        [_hideFromStatusBarHintLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [_hideFromStatusBarHintLabel setEditable:false];
        [_hideFromStatusBarHintLabel setSelectable:false];
        [_hideFromStatusBarHintLabel setBezeled:false];
        [_hideFromStatusBarHintLabel setBackgroundColor:[NSColor clearColor]];
        [_hideFromStatusBarHintLabel setAlignment:NSTextAlignmentCenter];
        
        _hintView = [[NSView alloc] initWithFrame:popoverRect];
        [_hintView addSubview:_hideFromStatusBarHintLabel];
        
        _hintVC = [[NSViewController alloc] init];
        [_hintVC setView:_hintView];
        
        _hideFromStatusBarHintPopover = [[NSPopover alloc] init];
        [_hideFromStatusBarHintPopover setContentViewController:_hintVC];
    }
    
    NSStatusBarButton *statusBarButton = [[self statusBar] button];
    [_hideFromStatusBarHintPopover showRelativeToRect:[statusBarButton bounds] ofView:statusBarButton preferredEdge:NSMinYEdge];
}

- (void)updateHideFromStatusBarHintPopover:(NSTimer*)aTimer
{
    NSDate* now = [NSDate date];
    [self setHideFromStatusBarHintLabelWithSeconds:[[_statusBarHideTimer fireDate] timeIntervalSinceDate:now]];
}

- (void)setHideFromStatusBarHintLabelWithSeconds:(NSUInteger)seconds
{
    [_hideFromStatusBarHintLabel setStringValue:[NSString stringWithFormat:@"Volume Control will hide after %ld seconds. Launch the app again to make the icon reappear in the menu bar.",seconds]];
}

#pragma mark - Music players

- (IBAction)toggleMusicPlayer:(id)sender
{
    if (sender == _iTunesBtn) {
        [preferences setBool:[sender state] forKey:@"iTunesControl"];
    }
    else if (sender == _spotifyBtn)
    {
        [preferences setBool:[sender state] forKey:@"spotifyControl"];
    }
    else if (sender == _dopplerBtn)
    {
        [preferences setBool:[sender state] forKey:@"dopplerControl"];
    }
    
    [preferences synchronize];
}

#pragma mark - NSMenuDelegate

- (IBAction)toggleHideVolumeWindow:(id)sender
{
    [self setHideVolumeWindow:![self hideVolumeWindow]];
}

- (void)setHideVolumeWindow:(bool)enabled
{
    _hideVolumeWindow=enabled;
    
    NSMenuItem* menuItem=[_statusMenu itemWithTag:HIDE_VOLUME_WINDOW_ID];
    [menuItem setState:[self hideVolumeWindow]];
    
    [preferences setBool:enabled forKey:@"hideVolumeWindowPreference"];
    [preferences synchronize];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    [self updatePercentages];
    
    if(!_Tapping)
    {
        updateSystemVolumeTimer = [NSTimer timerWithTimeInterval:updateSystemVolumeInterval target:self selector:@selector(updateSystemVolume:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:updateSystemVolumeTimer forMode:NSRunLoopCommonModes];
    }
    
    [_hideFromStatusBarHintPopover close];
    menuIsVisible=true;
}

- (void)menuDidClose:(NSMenu *)menu
{
    menuIsVisible=false;
    if([self hideFromStatusBar])
        [self showHideFromStatusBarHintPopover];
    
    if(updateSystemVolumeTimer)
    {
        [updateSystemVolumeTimer invalidate];
        updateSystemVolumeTimer = nil;
    }
}

@end
