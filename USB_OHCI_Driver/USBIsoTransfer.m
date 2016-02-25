/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#include "USBIsoTransfer.h"

@implementation USBIsoTransfer

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

    /* The -Physical- memory location must be aligned to 32-byte boundary */
    /* Allocate wired-down kernel memory */
    buflength = 2*sizeof(iso_td_t);

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

    /* Align physical ED to 32-byte boundary */
    if(physReg & 0x0000001F) physAligned = (physReg+0x0020) & 0xFFFFFFE0;
    else physAligned = physReg;

    offset = physAligned - physReg;
    physicalAddress = physAligned;

    descriptor = (iso_td_t *)(bufstart + offset);

    descriptor->dword0.word = 0;
    descriptor->dword1.word = 0;
    descriptor->dword2.word = 0;
    descriptor->dword3.word = 0;
    descriptor->dword4.word = 0;
    descriptor->dword5.word = 0;
    descriptor->dword6.word = 0;
    descriptor->dword7.word = 0;

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


- (iso_td_t *)descriptor
{
    return (iso_td_t *)descriptor;
}


@end
