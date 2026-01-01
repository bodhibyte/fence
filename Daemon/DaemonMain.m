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
    [SCSentry startSentry: @"org.eyebeam.selfcontrold"];
    SCDaemon* daemon = [SCDaemon sharedDaemon];
    [daemon start];

    // never gonna give you up, never gonna let you down, never gonna run around and desert you...
    [[NSRunLoop currentRunLoop] run];

    return 0;
}
