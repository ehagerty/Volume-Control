//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioServices.h>
#import "AppDelegate.h"

@interface SystemApplication : NSObject{
    
    NSAppleScript *ASSystemVolume;
    NSAppleEventDescriptor* AEsetVolume;
    NSAppleEventDescriptor* AEgetVolume;
    
@private
    
    NSInteger osxVersion;
    AppDelegate* appDelegate;
}

-(id)initWithVersion:(NSInteger)osxVersion andWithAppDelegate:(AppDelegate*)appDelegate;
    
@property (assign, nonatomic) double currentVolume;  // The sound output volume (0 = minimum, 100 = maximum)
@property (assign, nonatomic) double oldVolume;
@property (assign, nonatomic) double doubleVolume;

@end
