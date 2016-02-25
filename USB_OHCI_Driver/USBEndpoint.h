/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#define KERNEL 1
#import <kernserv/kalloc.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>
#import <objc/List.h>
#import "usb.h"
#import "USBTransfer.h"

@interface USBEndpoint : Object
{
    int epType;
    BOOL forceToggle;
    unsigned int *bufstart,buflength;
    volatile ed_t *descriptor;
    volatile unsigned int physicalAddress;
    USBEndpoint *nextEndpoint;
    USBEndpoint *prevEndpoint;
    List *tdList;
}

- init;
- free;

- (id)tailTransfer;

- (int)numTDsQueued;
- queueTransfer:(id)newTransfer;
- (void)updateTailPointer;

- (void)deQueueTransfer:(USBTransfer *)transfer;
- (void)unLinkTransfer:(USBTransfer *)transfer;

- (ed_t *)descriptor;
- (unsigned int)physicalAddress;

- (void)setEndpointAddress:(int)newAddress;
- (int)endpointAddress;

- (void)setUsbAddress:(int)newAddress;
- (int)usbAddress;

- (void)setEndpointDir:(int)newDir;
- (int)endpointDir;

- (void)setEndpointFormat:(int)newFormat;
- (int)endpointFormat;

- (void)nextEndpoint:(USBEndpoint *)newNext;
- (USBEndpoint *)nextEndpoint;

- (void)prevEndpoint:(USBEndpoint *)newPrev;
- (USBEndpoint *)prevEndpoint;


- (void)setMaxPacketSize:(int)newSize;
- (unsigned int)maxPacketSize;

- (void)skipFlag:(BOOL)flag;
- (unsigned int)skipFlag;

- (void)setSpeed:(int)newSpeed;
- (int)speed;

- (BOOL)isHalted;

- (void)type:(int)newType;
- (int)type;

- (id)transferForPhysicalTD:(unsigned int)physAddress;

- (BOOL)forceToggle;
- (void)forceToggle:(BOOL)toggleFlag;


- printTDList;

@end
