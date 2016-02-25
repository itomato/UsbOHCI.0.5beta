/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#import <objc/List.h>
#import "USBEndpoint.h"
#import "USBTransfer.h"

@interface USBDevice : Object
{
    char *productDescription;
    BOOL hasDeviceDriver;
    BOOL hardwareIsUp;
    int hubAddress;
    int hardwareHubPort;

    int usbAddress;
    int usbClass;
    int usbSubClass;
    id deviceDriver;
    List *endpointList;
    
}

- init;
- free;
- (BOOL)hasDeviceDriver;
- (void)hasDeviceDriver:(BOOL)hasDriver;

- (BOOL)hardwareIsUp;
- (void)hardwareIsUp:(BOOL)isUp;

- (int)hubAddress;
- (void)hubAddress:(int)newAddress;

- (int)hardwareHubPort;
- (void)hardwareHubPort:(int)newPort;

- (void)deviceDriver:(id)driver;
- (USBDevice *)driver;

- (id)controlEndpoint;

- (unsigned int)physicalControlED;
- (ed_t *)controlED;

- usbAddress:(int)newAddress;
- (int)usbAddress;

- (void)addEndpoint:(id)newEndpoint;
- (id)endpointAtIndex:(int)index;
- (USBEndpoint *)endpointForNumber:(int)endpointNum direction:(int)dataDir;

- (void)setUsbClass:(int)newClass;
- (int)usbClass;

- (void)setUsbSubClass:(int)newSubClass;
- (int)usbSubClass;

- (id)transferForPhysicalTD:(unsigned int)physAddress;
- (id)endpointForPhysicalTD:(unsigned int)physAddress;

- (void)idleEndpoints;
- (void)activateEndpoints;

- (char *)description;
- (void)description:(char *)newDesc;


@end
