/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#define KERNEL 1
#import <kernserv/kalloc.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>
#import "ohci.h"
#import "usb.h"

@interface USBTransfer : Object
{
    unsigned int *bufstart,buflength;
    volatile td_t *descriptor;
    volatile unsigned int physicalAddress;

    /*  Data packet */
    BOOL localData;
    volatile unsigned char *dataPacket;
    volatile unsigned int physDataPacket;
    unsigned int ndata,nalloced;
}

- init;
- free;

- (td_t *)descriptor;
- (unsigned int)physicalAddress;

- allocDataPacket:(int)nbytes;
- (unsigned char *)dataPacket;
- (unsigned int)physDataPacket;

- (BOOL)deQueued;
- (void)setDirection:(int)tdDir;

@end


