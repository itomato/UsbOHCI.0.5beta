/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#import "USBTransfer.h"

@implementation USBTransfer

- init
{
    unsigned int physReg,physAligned,offset;
    IOReturn ioerr;

    [super init];
    localData = NO;
    dataPacket = NULL;
    nalloced = 0;
    ndata = 0;
    physDataPacket = 0;

    /* The -Physical- memory location must be aligned to 16-byte boundary */
    /* Allocate wired-down kernel memory */
    buflength = 2*sizeof(td_t);

    bufstart = IOMalloc(buflength);

    if(bufstart==NULL) {
	IOLog("Kernel Out-Of-Memeory Allocating USB Transfer\n");
	return nil;
    }

    /* Translate to physical memory space */
    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)bufstart, &physReg);
    if(ioerr != IO_R_SUCCESS) {
	IOLog("Kernel Can't translate Transfer Descriptor to physical memory location\n");
	return nil;
    }

    /* Align physical ED to 16-byte boundary */
    if(physReg & 0x0000000F) physAligned = (physReg+0x0010) & 0xFFFFFFF0;
    else physAligned = physReg;

    offset = physAligned - physReg;
    physicalAddress = physAligned;

    descriptor = (td_t *)(bufstart + offset);

    descriptor->dword0.field.undef1 = 0;
    descriptor->dword0.field.bufferRounding = 1;
    descriptor->dword0.field.directionPID = DIR_IN;
    descriptor->dword0.field.delayInterrupt = NO_INTERRUPT;
    descriptor->dword0.field.dataToggle = 0;
    descriptor->dword0.field.errorCount = 0;
    descriptor->dword0.field.conditionCode = 0xF;

    descriptor->dword1.field.currentPointer = 0;

    descriptor->dword2.field.undef1 = 0;
    descriptor->dword2.field.nextTD = 0;

    descriptor->dword3.field.bufferEnd = 0xFFFFFFFF;

    return self;
}

- free
{
    IOFree((void *)bufstart, (int)buflength);
    if(localData == YES) {
	if(dataPacket != NULL)
	    IOFree((void *)dataPacket, (int)nalloced);
    }

    return [super free];
}



- initWithData:(int)nbytes
{
    if([self init]==nil) return nil;
    if([self allocDataPacket:nbytes]==nil) return nil;
    return self;
}


- allocDataPacket:(int)nbytes
{
    IOReturn i,ioerr;

    if(nbytes < 16) nalloced = 16;
    else nalloced = nbytes;

    dataPacket = (unsigned char *)IOMalloc(nalloced);
    if(dataPacket==NULL) {
	IOLog("USB OHCI Driver:  ** Memory Error **  Can't allocate data packet\n");
	return nil;
    }

    for(i=0; i<nalloced; i++) dataPacket[i] = 0;

    if(dataPacket==NULL) {
	IOLog("USB OHCI Driver:  Can't Allocate TD Data Packet\n");
	return nil;
    }

    /* Get physical address */
    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dataPacket, (unsigned int *)&physDataPacket);
    if(ioerr != IO_R_SUCCESS) {
	IOLog("Kernel Can't translate TD Data Packet to physical memory location\n");
	return nil;
    }

    ndata = nalloced;
    descriptor->dword1.field.currentPointer = physDataPacket;
    descriptor->dword3.field.bufferEnd = physDataPacket+nbytes-1;

    localData = YES;

    return self;
}


- (BOOL)deQueued
{
    if((descriptor->dword1.field.currentPointer == 0) ||
       descriptor->dword1.field.currentPointer != physDataPacket)
	  return YES;

    return NO;
}

- (void)setDirection:(int)tdDir
{
    descriptor->dword0.field.directionPID = tdDir;
    return;
}


- (td_t *)descriptor
{
    return (td_t *)descriptor;
}


- (unsigned int)physicalAddress
{
    return physicalAddress;
}


- (unsigned char *)dataPacket
{
    return (unsigned char *)dataPacket;
}

- (unsigned int)physDataPacket
{
    return physDataPacket;
}


@end

