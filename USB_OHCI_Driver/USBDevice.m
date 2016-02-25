/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#import "USBDevice.h"

@implementation USBDevice

- init
{
    USBEndpoint *control;
    USBTransfer *transfer;

    [super init];
    endpointList = [[List alloc] init];
    usbAddress = 0;
    deviceDriver = nil;
    productDescription = NULL;

    /* Make a default control endpoint */
    control = [[USBEndpoint alloc] init];
    [endpointList addObject:control];

    /* Make and Queue an empty Transfer Descriptor */
    transfer = [[USBTransfer alloc] init];
    [control queueTransfer:transfer];

    hasDeviceDriver = NO;
    hardwareIsUp = YES;

    return self;
}

- free
{
    if(productDescription != NULL)
      free(productDescription);

    [endpointList freeObjects];
    [endpointList free];
    
    return [super free];
}


- (BOOL)hasDeviceDriver
{
    return hasDeviceDriver;
}


- (void)hasDeviceDriver:(BOOL)hasDriver
{
    hasDeviceDriver = hasDriver;
}


- (BOOL)hardwareIsUp
{
    return hardwareIsUp;
}


- (void)hardwareIsUp:(BOOL)isUp
{
    hardwareIsUp = isUp;
}

- (int)hubAddress
{
    return hubAddress;
}


- (void)hubAddress:(int)newAddress
{
    hubAddress = newAddress;
}


- (int)hardwareHubPort
{
    return hardwareHubPort;
}


- (void)hardwareHubPort:(int)newPort
{
    hardwareHubPort = newPort;
}


- (void)deviceDriver:(id)driver
{
    deviceDriver = driver;
    hasDeviceDriver = YES;
    return;
}


- (USBDevice *)driver
{
    return deviceDriver;
}

- (id)controlEndpoint
{
    return [endpointList objectAt:0];
}

- (unsigned int)physicalControlED
{
    return [[endpointList objectAt:0] physicalAddress];
}

- (ed_t *)controlED
{
    return [(USBEndpoint *)[endpointList objectAt:0] descriptor];
}


- usbAddress:(int)newAddress
{
    int i;

    usbAddress = newAddress;
    for(i=0; i<[endpointList count]; i++) {
	ed_t *ed = [(USBEndpoint *)[endpointList objectAt:i] descriptor];
	ed->dword0.field.funcAddress = usbAddress;
    }

    return self;
}

- (int)usbAddress
{
    return usbAddress;
}


- (void)addEndpoint:(id)newEndpoint
{
    [endpointList addObject:newEndpoint];

    if([newEndpoint usbAddress] != usbAddress) 
	[newEndpoint setUsbAddress:usbAddress];

    return;
}

    
- (id)endpointAtIndex:(int)index
{
    return [endpointList objectAt:index];
}


- (id)endpointForNumber:(int)endpointNum direction:(int)dataDir
{
    int iep,nep;

    nep = [endpointList count];

    for(iep=0; iep<nep; iep++) {
	USBEndpoint *ep = [endpointList objectAt:iep];
	int epDir = [ep endpointDir];
	    
	if(([ep endpointAddress] == endpointNum) &&
	   ((epDir == dataDir) || (epDir == DIR_TD)))
	    return ep;
    }

    return nil;
}


- (void)setUsbClass:(int)newClass
{
    usbClass = newClass;
    return;
}


- (int)usbClass
{
    return usbClass;
}


- (void)setUsbSubClass:(int)newSubClass
{
    usbSubClass = newSubClass;
    return;
}


- (int)usbSubClass
{
    return usbSubClass;
}

- (id)transferForPhysicalTD:(unsigned int)physAddress
{
    int iep, neps;
    USBTransfer *transfer = nil;

    neps = [endpointList count];

    for(iep=0; iep<neps; iep++) {
	USBEndpoint *currentEndpoint = [endpointList objectAt:iep];
	transfer = [currentEndpoint transferForPhysicalTD:physAddress];
	if(transfer != nil) {
	    return transfer;
	}
    }

    return nil;
}

- (id)endpointForPhysicalTD:(unsigned int)physAddress
{
    int iep, neps = [endpointList count];
    USBTransfer *transfer;

    for(iep=0; iep<neps; iep++) {
	USBEndpoint *currentEndpoint = [endpointList objectAt:iep];
	transfer = [currentEndpoint transferForPhysicalTD:physAddress];
	if(transfer != nil) return currentEndpoint;
    }

    return nil;
}


- (void)idleEndpoints
{
    int iep, neps;

    neps = [endpointList count];

    for(iep=0; iep<neps; iep++)
      [(USBEndpoint *)[endpointList objectAt:iep] descriptor]->dword0.field.skip = 1;

    return;
}


- (void)activateEndpoints
{
    int iep, neps;

    neps = [endpointList count];

    for(iep=0; iep<neps; iep++)
      [(USBEndpoint *)[endpointList objectAt:iep] descriptor]->dword0.field.skip = 0;

    return;
}  

    
- (char *)description
{
    return productDescription;
}


- (void)description:(char *)newDesc
{
    if(productDescription) free(productDescription);

    productDescription = malloc(1+strlen(newDesc));
    strcpy(productDescription,newDesc);

    return;
}


@end
