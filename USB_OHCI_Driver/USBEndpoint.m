/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#import "USBEndpoint.h"

@implementation USBEndpoint

- init
{
    unsigned int physReg,physAligned,offset;
    IOReturn ioerr;

    [super init];
    forceToggle = NO;

    /* Make a List to hold Transfer Descriptor Objects queued to this ED */
    tdList = [[List alloc] init];
    nextEndpoint = nil;
    prevEndpoint = nil;

    /* The -Physical- memory location must be aligned to 16-byte boundary */
    /* Allocate wired-down kernel memory */
    buflength = 2*sizeof(ed_t);

    /* Allocate memory for the descriptor */
    bufstart = IOMalloc(buflength);

    if(bufstart==NULL) {
	IOLog("Kernel Out-Of-Memeory Allocating USB Endpoint\n");
	return nil;
    }

    /* Translate to physical memory space */
    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)bufstart, &physReg);
    if(ioerr != IO_R_SUCCESS) {
	IOLog("Kernel Can't translate Endpoint Descriptor to physical memory location\n");
	return nil;
    }

    /* Align physical ED to 16-byte boundary */
    if(physReg & 0x0000000F) physAligned = (physReg+0x0010) & 0xFFFFFFF0;
    else physAligned = physReg;

    offset = physAligned - physReg;
    physicalAddress = physAligned;
    descriptor = (ed_t *)(bufstart + offset);

    descriptor->dword0.field.funcAddress = 0;
    descriptor->dword0.field.epAddress = 0;
    descriptor->dword0.field.direction = 0;
    descriptor->dword0.field.speed = 0;
    descriptor->dword0.field.skip = 1;
    descriptor->dword0.field.format = 0;
    descriptor->dword0.field.maxPacket = 8;
    descriptor->dword0.field.undef1 = 0;

    descriptor->dword1.field.undef1 = 0;
    descriptor->dword1.field.tailPointer = 0;

    descriptor->dword2.field.halt = 0;
    descriptor->dword2.field.toggleCarry = 0;
    descriptor->dword2.field.zero = 0;
    descriptor->dword2.field.headPointer = 0;

    descriptor->dword3.field.undef1 = 0;
    descriptor->dword3.field.nextED = 0;

    return self;
}


- free
{
    IOFree(bufstart,(int)buflength);
    [tdList freeObjects];
    [tdList free];

    return [super free];
}


- (id)tailTransfer
{
    return [tdList lastObject];
}


- (int)numTDsQueued
{
    return [tdList count];
}


- queueTransfer:(USBTransfer *)newTransfer
{
    td_t *newTD;
    unsigned int newPhysTD;

    newTD = [newTransfer descriptor];
    newPhysTD = [newTransfer physicalAddress];

    /*  We don't update tail pointer here, that
     *  way we can queue several TD's and then
     *  process them all by updating the tailPointer
     */

    if(descriptor->dword1.field.tailPointer==0) {
	descriptor->dword1.field.tailPointer = (newPhysTD >> 4);
	descriptor->dword2.field.headPointer = (newPhysTD >> 4);
    }
    else {
	/* Point nextTD of current tailTD to new TD */
	td_t *tailTD = [(USBTransfer *)[tdList lastObject] descriptor];

	/* Just for grins, check that the nextTD of the tailTD is NULL */
	if(tailTD->dword2.field.nextTD != 0)
	    IOLog("USB OHCI Driver:  TD QUEUE ERROR.  Last Queued TD has non-null value in nextTD\n");

	tailTD->dword2.field.nextTD = (newPhysTD >> 4);
    }

    newTD->dword2.field.nextTD = 0;
    [tdList addObject:newTransfer];

    return self;
}



- (void)deQueueTransfer:(USBTransfer *)transfer
{
    /* Remove TD from tdList */
    [tdList removeObject:transfer];

    /* Free memory and kill the TD */
    [transfer free];

    return;
}


- (void)unLinkTransfer:(USBTransfer *)transfer
{
    USBTransfer *prevTransfer,*thisTransfer,*nextTransfer;
    unsigned int prevPhysTD,thisPhysTD,nextPhysTD;
    unsigned int targPhysTD = [transfer physicalAddress];

    /*  Get first TD, walk through the list till
     *  you find this one
     */

    prevPhysTD = 0;
    prevTransfer = nil;

    nextPhysTD = 0;
    nextTransfer = nil;
   
    thisPhysTD = (descriptor->dword2.field.headPointer << 4);
    if(thisPhysTD == 0) return;

    thisTransfer = [self transferForPhysicalTD:thisPhysTD];
    if(thisTransfer == nil) {
      IOLog("BIG Trouble.  Can't find USBTransfer for physical address %d\n",thisPhysTD);
      return;
    }
    
    while(thisPhysTD != targPhysTD) {

        prevPhysTD = thisPhysTD;
	prevTransfer = thisTransfer;

	thisPhysTD = [thisTransfer descriptor]->dword2.field.nextTD << 4;
	if(thisPhysTD == 0) break;

	thisTransfer = [self transferForPhysicalTD:thisPhysTD];
	if(thisTransfer == nil) {
	    IOLog("USBEndpoint Big trouble.  Can't find USBTransfer for physical address %d\n",thisPhysTD);
	    return;
	}
    }

    if(thisPhysTD != targPhysTD) {
      IOLog("USBEndpoint BIG trouble.  Can't find TD for physical address %d on chain\n",thisPhysTD);
      return;
    }

    nextPhysTD = ([thisTransfer descriptor]->dword2.field.nextTD << 4);
    if(nextPhysTD > 0) 
      nextTransfer = [self transferForPhysicalTD:nextPhysTD];

    /* If this is the only TD queued, leave it alone */
    if((prevPhysTD == 0) && (nextPhysTD == 0)) return;


    /* Set physical pointers */
    if(prevTransfer)
      [prevTransfer descriptor]->dword2.field.nextTD = (nextPhysTD >> 4);
    else
      descriptor->dword2.field.headPointer = nextPhysTD >> 4;

    /* Free the desired transfer object */
    [tdList removeObject:transfer];
    [transfer free];

    return;
}
	
	
/* Updating the tail pointer separately allows us to queue several
   TDs individually without processing them until all have been
   queued
   */

- (void)updateTailPointer
{
    unsigned int physAddr;

    physAddr = [[tdList lastObject] physicalAddress];
    descriptor->dword1.field.tailPointer = (physAddr >> 4);

    return;
}

    
- (ed_t *)descriptor
{
    return (ed_t *)descriptor;
}


- (unsigned int)physicalAddress
{
    return physicalAddress;
}

- (void)setEndpointAddress:(int)newAddress
{
    descriptor->dword0.field.epAddress = newAddress;
    return;
}


- (int)endpointAddress
{
    return descriptor->dword0.field.epAddress;
}
    

- (void)setUsbAddress:(int)newAddress
{
    descriptor->dword0.field.funcAddress = newAddress;
    return;
}


- (int)usbAddress
{
    return descriptor->dword0.field.funcAddress;
}


/* newDir value of zero indicates an OUT endpoint (pg 228 USB Book) */
- (void)setEndpointDir:(int)newDir
{
    descriptor->dword0.field.direction = newDir;
    return;
}

    
- (int)endpointDir
{
    return descriptor->dword0.field.direction;
}


- (void)setEndpointFormat:(int)newFormat
{
    descriptor->dword0.field.format = newFormat;
    return;
}

    
- (int)endpointFormat
{
    return descriptor->dword0.field.format;
}


- (void)nextEndpoint:(USBEndpoint *)newNext
{
    nextEndpoint = newNext;
    return;
}


- (USBEndpoint *)nextEndpoint
{
    return nextEndpoint;
}


- (void)prevEndpoint:(USBEndpoint *)newPrev
{
    prevEndpoint = newPrev;
    return;
}


- (USBEndpoint *)prevEndpoint
{
    return prevEndpoint;
}



- (void)skipFlag:(BOOL)flag
{
    if(flag==YES)
	descriptor->dword0.field.skip = 1;
    else
	descriptor->dword0.field.skip = 0;
	
    return;
}

- (unsigned int)skipFlag
{
    return descriptor->dword0.field.skip;
}


- (void)setSpeed:(int)newSpeed
{
    descriptor->dword0.field.speed = newSpeed;
    return;
}

- (int)speed
{
    return descriptor->dword0.field.speed;
}


- (BOOL)isHalted
{
    return descriptor->dword2.field.halt;
}


- (void)type:(int)newType
{
    epType = newType;
}

- (int)type
{
    return epType;
}



- (void)setMaxPacketSize:(int)newSize
{
    descriptor->dword0.field.maxPacket = newSize;
}


- (unsigned int)maxPacketSize
{
    return descriptor->dword0.field.maxPacket;
}


- (id)transferForPhysicalTD:(unsigned int)physAddress
{
    int itd,ntds;

    ntds = [tdList count];

    for(itd=0; itd<ntds; itd++) {
	USBTransfer *currentTransfer = [tdList objectAt:itd];
	if([currentTransfer physicalAddress] == physAddress) {
	    return currentTransfer;
	}
    }

    return nil;
}

- (BOOL)forceToggle
{
    return forceToggle;
}


- (void)forceToggle:(BOOL)toggleFlag
{
     forceToggle = toggleFlag;
}
    



- printTDList
{
    int iTD;

    IOLog("                     ED HeadP:    %08x\n\n",descriptor->dword2.word);
    IODelay(3000);

    for(iTD=0; iTD<[tdList count]; iTD++) {
	td_t *currentTD = [(USBTransfer *)[tdList objectAt:iTD] descriptor];
	unsigned int physTD = [(USBTransfer *)[tdList objectAt:iTD] physicalAddress];

	IOLog("                   kernel:    %08x\n",(unsigned int)currentTD);
	IODelay(3000);
	IOLog("                 physical:    %08x\n",physTD);
	IODelay(3000);
	IOLog("                   nextTD:    %08x\n\n",(unsigned int)(currentTD->dword2.word));
	IODelay(3000);

#if 0	
	IOLog("                    flags:    %08x\n",(unsigned int)(currentTD->dword0.word));
	IOLog("           currentPointer:    %08x\n",(unsigned int)(currentTD->dword1.word));
	IOLog("                   nextTD:    %08x\n",(unsigned int)(currentTD->dword2.word));
	IOLog("                bufferEnd:    %08x\n\n",(unsigned int)(currentTD->dword3.word));
#endif
	
	IODelay(2000000);
    }

    return self;
}


	
@end

