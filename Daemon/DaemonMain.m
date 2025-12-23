//
//  DaemonMain.m
//  SelfControl
//
//  Created by Charlie Stigler on 5/28/20.
//

#import <Foundation/Foundation.h>
#import "SCDaemon.h"

// Entry point for the SelfControl daemon process (selfcontrold)
int main(int argc, const char *argv[]) {
    NSLog(@"selfcontrold: === DAEMON STARTING ===");

    NSLog(@"selfcontrold: Step 1 - Initializing Sentry...");
    [SCSentry startSentry: @"org.eyebeam.selfcontrold"];
    NSLog(@"selfcontrold: Step 1 - Sentry initialized");

    NSLog(@"selfcontrold: Step 2 - Getting daemon singleton...");
    SCDaemon* daemon = [SCDaemon sharedDaemon];
    NSLog(@"selfcontrold: Step 2 - Daemon singleton created");

    NSLog(@"selfcontrold: Step 3 - Starting daemon...");
    [daemon start];
    NSLog(@"selfcontrold: Step 3 - Daemon started");

    NSLog(@"selfcontrold: === RUNNING FOREVER ===");

    // never gonna give you up, never gonna let you down, never gonna run around and desert you...
    [[NSRunLoop currentRunLoop] run];

    return 0;
}
