/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 *
 * Version 0.5 beta version October 1, 2000
 */

#import "UsbOHCI.h"

/*
 *  This code makes references to the following documents:
 *
 *       o  Open Host Controller Interface Specification for USB
 *          Release 1.0a    Compaq, Microsoft, National Semiconductor
 *	    9/14/99   Available here:
 *
 *          http://www6.compaq.com/productinfo/development/openhci.html
 *
 *
 *       o  USB Serial Bus Specification
 *          Revision 1.1  Compaq, Intel, Microsoft, NEC
 *          9/98   Available here:
 *
 *          http://www.usb.org/developers/data/usbspec.zip
 *
 *
 *       o  FireLink 82C861 PCI-to-USB Bridge Data Book Revision 1.0
 *          May 27, 1998.   OPTi Inc.  Available here:
 *
 *          ftp://ftp.opti.com/pub/chipsets/system/firelink/usb1.pdf
 *
 *
 *       o  Universal Serial Bus System Architecture
 *          Don Anderson, MindShare Inc.
 *          Addison-Wesley
 *          ISBN  0-201-46137-4
 *
 *
 *       o  PCI System Architecture, Fourth Edition
 *          Tom Shanley / Don Anderson, MindShare Inc.
 *          Addison-Wesley
 *          ISBN 0-201-30974-2
 *
 *
 *  Initialization roughly follows the plan outlined
 *  in the OHCI Specification in Chapter 5
 *
 */

static char *usberrstr[] = {
  "None",
  "CRC",
  "BIT STUFFING",
  "DATA TOGGLE MISMATCH",
  "STALL",
  "DEVICE NOT RESPONDING",
  "PID CHECK FAILURE",
  "UNEXPECTED PID",
  "DATA OVERRUN",
  "DATA UNDERRUN",
  "","",
  "BUFFER OVERRUN",
  "BUFFER UNDERRUN",
  "",
  "NOT ACCESSED",
  "TIMEOUT"
};

static UsbOHCI *ohciDriver;
static instPort;

@implementation UsbOHCI

+ (BOOL)probe: deviceDescription
{
    ohciDriver = [self alloc];
    if(ohciDriver == nil) {
	IOLog("usb -  Failed to allocate driver instance\n");
	IOSleep(100);
	return NO;
    }

    IOLog("\nUSB Open Host Controller Driver (OHCI) by Howard R. Cole\n");

    if([ohciDriver probeForUSB_OHCI:deviceDescription]==nil) {
        IOLog("Hardware is not a USB OHCI device\n");
	IOSleep(100);
        return NO;
    }

    if([ohciDriver initFromDeviceDescription:deviceDescription] == nil) {
        IOLog("Probe Failed.\n");
	IOSleep(100);
        return NO;
    }

    return YES;
}


/*
 *  This method checks the value of several PCI 
 *  registers to determine if a USB Controller is
 *  attached.
 *
 */

- probeForUSB_OHCI:(id)deviceDescription
{
    id configTable;
    IOPCIConfigSpace configSpace;
    const char *value = NULL;
    int class,subclass,progIF;
    IOReturn irtn;

    /* Initialize configuration table from Default.table  */
    configTable = [deviceDescription configTable];

    /* Initialize configuration Registers from board */
    if(irtn = [IODirectDevice getPCIConfigSpace:&configSpace
			      withDeviceDescription:deviceDescription]) {
	IOLog("usb - Can\'t get configSpace (%s); ABORTING\n", 
	      [IODirectDevice stringFromReturn:irtn]);
	IOSleep(100);
	return [self free];
    }

    /* Get the value of the Bus Type in Config Table */
    value = [configTable valueForStringKey:"Bus Type"];
    if(value == NULL) {
	IOLog("usb -  No Bus Type in config Table\n");
	IOSleep(100);
	return [self free];
    }

    /* Check if the bus type is PCI */
    if(strcmp(value, "PCI") !=0) {
	IOLog("usb - Bad Bus Type (%s) in config table\n",value);
	IOSleep(100);
	return [self free];
    }

    /*
     *  Definitions for the correct values of these
     *  PCI registers can be found beginning on page
     *  353 of the PCI book mentioned above
     *
     */

    /*  Check class for Serial Bus Controller (pg 358, PCI Book) */
    class = (configSpace.ClassCode >> 16) & 0xFF;
    if(class != 0x0C) {
        IOLog("usb -  PCI card is class: %02xh\n",class);
	IOSleep(100);
        IOLog("                  Serial bus controller class should be 0x0c\n");
	IOSleep(100);
        return [self free];
    }

    /*  Check subclass for USB support (pg 365, PCI book)  */
    subclass = (configSpace.ClassCode >> 8) & 0xFF;
    if(subclass != 0x03) {
        IOLog("usb -  PCI card is subclass: %02xh\n",subclass);
	IOSleep(100);
        IOLog("                  USB controller subclass should be 0x03\n");
	IOSleep(100);
        return [self free];
    }

    /*  Check progIF for OHCI support (pg 365, PCI book)  */
    progIF = configSpace.ClassCode & 0xFF;
    if(progIF != 0x10) {
        IOLog("usb -  PCI card is programming interface: %02xh\n",progIF);
	IOSleep(100);
        IOLog("                  OHCI programming interface should be 0x10\n");
	IOSleep(100);
        return [self free];
    }

    return self;
}
    


/*  This is the high-level Initialization routine */

- initFromDeviceDescription: deviceDescription
{
    IOReturn ioerr;
    unsigned int baseAddress,irq;
    static void timeoutdaemon(void *arg);
    static void plumberdaemon(void *arg);
    static void installdaemon(void *driver);
    static void setIgnoreRHSC(void *arg);

    instPort = 0;

    if([super initFromDeviceDescription:deviceDescription] == nil) {
	IOLog("usb - Can't init IODirectDevice superclass\n");
	IOSleep(100);
	return nil;
    }

    baseAddress = [self initMemBaseFromDeviceDescription:deviceDescription];
    if(baseAddress == -1) {
        IOLog("usb - Can't init Memory Base\n");
	IOSleep(100);
        return nil;
    }

    /* At this point, all OHCI Registers can be accessed by the driver */

    if([self initOHCIRegistersFromDeviceDescription:deviceDescription]==nil) {
        IOLog("usb - Can't init OHCI registers\n");
	IOSleep(100);
        return nil;
    }

    /*  At this point, memory has been allocated for descriptors
     *  used in all Endpoint Head Lists: control, bulk, interrupt
     *  and isochronous.
     */

    irq = [self initIRQFromDeviceDescription:deviceDescription];
    if(irq == -1) {
	IOLog("usb - Can't reserve IRQ for USB PCI device\n");
	IOSleep(100);
	return nil;
    }

    /*  At this point PCI interrupts are ready */


    /* Set up IPC synchronization to Utility Threads */
    commandLock = [[NXLock alloc] init];
    processedLock = [[NXLock alloc] init];
    errorLock = [[NXLock alloc] init];
    timeLock = [[NXLock alloc] init];

    usbCommandList = [[List alloc] init];
    usbProcessedList = [[List alloc] init];
    errorTransferList = [[List alloc] init];
    timeoutList = [[List alloc] init];
    
    if([self startIOThread] != IO_R_SUCCESS) {
	IOLog("usb -  Can't start IO Thread\n");
	IOSleep(100);
	return nil;
    }

    [self setName:"UsbOHCI0"];
    [self registerDevice];

    ioerr = [self enableAllInterrupts];
    if(ioerr != IO_R_SUCCESS) {
	IOLog("usb -  Can't enable IO Thread Interrupts\n");
	IOSleep(100);
    }

    /*
     *  mshPort must be initialized -after- startIOThread,
     *  otherwise, self has no interruptPort at all.
     */
    msgPort = IOConvertPort([self interruptPort], IO_KernelIOTask, IO_Kernel);
    machMessage.msg_id = IO_COMMAND_MSG;
    machMessage.msg_size = sizeof(machMessage);
    machMessage.msg_type = MSG_TYPE_NORMAL;
    machMessage.msg_remote_port = msgPort;
    machMessage.msg_local_port = PORT_NULL;

    /* Spin off a thread to handle USB packet errors */
    plumberLock = [[NXConditionLock alloc] initWith:PLUMBER_IDLE];
    IOForkThread(plumberdaemon, self);

    /* Spin off a thread to handle USB packet timeouts */
    timeoutLock = [[NXConditionLock alloc] initWith:TIMEOUT_IDLE];
    IOForkThread(timeoutdaemon, self);

    /* Spin off a thread to handle hot device installation */
    installLock = [[NXConditionLock alloc] initWith:INSTALL_IDLE];
    IOForkThread(installdaemon, self);


    /* Initialize usb hardware registers, begin USB frame processing */
    [self startHardware];

    /* Turn on interrupts, ignore changes on Root Hub for now */
    ignoreRHSC = YES;
    *((unsigned int *)(HcBase+HcInterruptDisable)) = HC_ALL_INTRS;
    *((unsigned int *)(HcBase+HcInterruptEnable)) = HC_SO | HC_WDH | HC_RD | HC_UE | HC_RHSC | HC_MIE;

    /* Set Ports to individual power control */
    [self initPortPower];

    /* Discover how many ports there are, etc */
    [self initRootHubConfiguration];

    /* Query USB for devices */
    [self enumerateDevices];

    /* Clear interrupt conditions  */
    *((unsigned int *)(HcBase+HcRhPortStatus(1))) = HC_CSC | HC_PESC | HC_PSSC | HC_POCIC | HC_PRSC;
    *((unsigned int *)(HcBase+HcRhPortStatus(2))) = HC_CSC | HC_PESC | HC_PSSC | HC_POCIC | HC_PRSC;
    *((unsigned int *)(HcBase+HcInterruptStatus)) = 0x7F;

    /* Now we can watch for Hub changes */
    IOScheduleFunc(setIgnoreRHSC, self, 30);

    /*
     *  Controller is hot, devices are installed.
     *  WE'RE OUT OF HERE!!
     */

    IOLog("UsbOHCI0: Base=0x%08x, IRQ=%d\n",baseAddress,irq);

    return self;
}


/*
 *  This method's only purpose is to configure the memory base
 *  address of the USB registers.  We need to ascertain the
 *  physical address, and then map that into the kernel memory
 *  space
 *
 */

- (unsigned int)initMemBaseFromDeviceDescription:(id)deviceDescription
{
    id configTable;
    IOPCIConfigSpace configSpace;
    IOReturn irtn;
    int ibase;
    unsigned long baseAddress = 0;
    const char *configRange;
    char *dashptr;
    char configBase[24];
    unsigned long baseMask;
    unsigned int virtual;
    unsigned int asciihex_to_uint(char *);

    /* Initialize configuration table from Default.table  */
    configTable = [deviceDescription configTable];

    /* Initialize configuration Registers from board */
    if(irtn = [IODirectDevice getPCIConfigSpace:&configSpace
			      withDeviceDescription:deviceDescription]) {
	IOLog("usb - Can\'t get configSpace (%s); ABORTING\n", 
	      [IODirectDevice stringFromReturn:irtn]);
	IOSleep(100);
	return -1;
    }

    /* Scan all 6 base address registers, as per pg 384, PCI Book  */
    for(ibase=0; ibase<PCI_NUM_BASE_ADDRESS; ibase++) {

        /* Write all 1's to each base register, then read them back */
	/* If result is non-zero, register is implemented           */
        if(irtn = [IODirectDevice setPCIConfigData:0xFFFFFFFF 
                                        atRegister:0x10+4*ibase
                             withDeviceDescription:deviceDescription]) {
	    IOLog("usb -  Can't write configuration base register %d\n",ibase);
	    IOSleep(100);
            return -1;
	}

        if(irtn = [IODirectDevice getPCIConfigData:&baseMask
                                        atRegister:0x10+4*ibase
                            withDeviceDescription:deviceDescription]) {
	    IOLog("usb -  Can't read configuration base register %d\n",ibase);
	    IOSleep(100);
            return -1;
	}

        if((baseMask == 0) || ((baseMask & PCI_BASE_IO_BIT) == 1))  continue;

        break;
    }

    /* At this point, 'ibase' contains the index of the first base
       address register which is implemented */

    if(ibase>=PCI_NUM_BASE_ADDRESS) {
        IOLog("   Base Address Register not found on PCI card\n");
	IOSleep(100);
        return -1;
    }

    /* Set base address to the value in driver config file */
    configRange = [configTable valueForStringKey:"Memory Maps"];

    strncpy(configBase,configRange,23);
    dashptr = strchr(configBase,'-');
    if(dashptr) *dashptr = '\0';

    baseAddress = asciihex_to_uint(configBase);
    baseAddress &= baseMask;

    if(baseAddress == 0) {
        IOLog("   base address masks to ZERO.  Setting default address to 0x80000000\n");
	IOSleep(100);
        baseAddress = 0x80000000;
    }

    if(irtn = [IODirectDevice setPCIConfigData:baseAddress
                                    atRegister:0x10+4*ibase
                         withDeviceDescription:deviceDescription]) {
	IOLog("usb -  Can't set configuration base address register %d\n",ibase);
	IOSleep(100);
        return -1;
    }

    physicalHcBase = (unsigned int *)baseAddress;

    /* Get the virtual address in kernel memory space */
    irtn = IOMapPhysicalIntoIOTask(baseAddress, 0x0fff, &virtual);

    if(irtn != 0) {
        IOLog("  ***  Can't Map physical address %08lxh into Virtual kernel memory ***\n",
		baseAddress);
	IOSleep(100);
	return -1;
    }

    HcBase = (vm_address_t)virtual;

    return baseAddress;
}


/*
 *  This method allocates Endpoint Descriptor shared memory space
 *  which is used by both the hardware controller and this driver.
 *  The space is only allocated here, the hardware registers are
 *  set to these values later;  you can't change the value of
 *  shared memory pointer registers in the hardware unless the
 *  hardware controller is in the Suspend state.
 *
 */

- initOHCIRegistersFromDeviceDescription:(id)deviceDescription
{
    unsigned int revision;
    unsigned int physReg,physAlign;
    vm_offset_t startPage,endPage;
    unsigned int offset;
    int i,ioerr;
    USBEndpoint *controlEndpoint, *bulkEndpoint;
    USBTransfer *blankTransfer;
    

    /* Check OHCI Revision number.  Must be 0x10 */
    revision = *((unsigned int *)(HcBase + HcRevision));
    revision &= 0x000000FF;

    if(revision != 0x10) {
	IOLog("PCI USB Card is revision %04xh.  It must be revision 10h\n",revision);
	IOSleep(100);
	return [self free];
    }

    /*  Allocate 256 bytes of wired contiguous memory for the HCCA area
     *  aligned on a 256 byte boundary
     */
    hccaBufferFree = (vm_address_t)IOMalloc(1024);

    /* Get physical address */
    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), hccaBufferFree, &physReg);
    if(ioerr != IO_R_SUCCESS) {
	IOLog("usb -   Can't get Physical address of HCCA buffer\n");
	IOSleep(100);
	return nil;
    }

    /* Truncate to 256-byte boundary */
    if((physReg & 0x000000FF) != 0)
	physAlign = (physReg & 0xFFFFFF00) + 0x00000100;
    else
	physAlign = physReg;

    offset = physReg - physAlign;

    /* Make sure we don't cross a 4K Page boundary */
    startPage = physAlign & 0xFFFF8000;
    endPage = (physAlign+256) & 0xFFFF8000;

    if(startPage != endPage) {
	IOLog("usb -   Didn't Page align HCCA memeory buffer - try again bub\n");
	IOSleep(100);
	return nil;
    }


    hccaBufferBase = hccaBufferFree + offset;
    physicalHCCABufferBase = (unsigned int)physAlign;

    /* Zero out the buffer */
    for(i=0; i<256; i++) ((unsigned char *)(hccaBufferBase))[i] = 0;


    /* Initialize the device Endpoint lists */
    usbDeviceList = [[List alloc] init];

    controlEDList = [[List alloc] init];
    bulkEDList = [[List alloc] init];

    interrupt32EDList = [[List alloc] init];
    interrupt16EDList = [[List alloc] init];
    interrupt08EDList = [[List alloc] init];
    interrupt04EDList = [[List alloc] init];
    interrupt02EDList = [[List alloc] init];
    interrupt01EDList = [[List alloc] init];

    isochronousEDList = [[List alloc] init];

    /* Make dummy Endpoint Descriptors for the Control Head, Bulk Head */
    controlEndpoint = [[USBEndpoint alloc] init];
    blankTransfer = [[USBTransfer alloc] init];
    [controlEndpoint queueTransfer:blankTransfer];
    [controlEDList addObject:controlEndpoint];

    bulkEndpoint = [[USBEndpoint alloc] init];
    blankTransfer = [[USBTransfer alloc] init];
    [bulkEndpoint queueTransfer:blankTransfer];
    [bulkEDList addObject:bulkEndpoint];

    /* Make dummy Endpoints to act as place-holders for 32ms interrupts in HCCA */
    for(i=0; i<32; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt32EDList addObject:newEndpoint];
    }

    /* Make dummy Endpoints to act as place-holders for 16ms interrupts in HCCA */
    for(i=0; i<16; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt16EDList addObject:newEndpoint];
    }

    /* Make dummy Endpoints to act as place-holders for 8ms interrupts in HCCA */
    for(i=0; i<8; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt08EDList addObject:newEndpoint];
    }

    /* Make dummy Endpoints to act as place-holders for 4ms interrupts in HCCA */
    for(i=0; i<4; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt04EDList addObject:newEndpoint];
    }

    /* Make dummy Endpoints to act as place-holders for 2ms interrupts in HCCA */
    for(i=0; i<2; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt02EDList addObject:newEndpoint];
    }

    /* Make dummy Endpoints to act as place-holders for 1ms interrupts in HCCA */
    for(i=0; i<1; i++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	blankTransfer = [[USBTransfer alloc] init];
	[newEndpoint queueTransfer:blankTransfer];
	[interrupt01EDList addObject:newEndpoint];
    }

    /*   Set up the interrupt tree as described on page 62 and 63
     *   of the OHCI spec
     */
    for(i=0; i<16; i++) {
	USBEndpoint *end32a = [interrupt32EDList objectAt:2*i];
	USBEndpoint *end32b = [interrupt32EDList objectAt:2*i+1];
	USBEndpoint *end16 = [interrupt16EDList objectAt:i];

	/* Set kernel pointers */
	[end32a nextEndpoint:end16];
	[end32b nextEndpoint:end16];
	[end16 prevEndpoint:end32a];

	/* Set physical pointer */
	[end32a descriptor]->dword3.field.nextED = ([end16 physicalAddress] >> 4);
	[end32b descriptor]->dword3.field.nextED = ([end16 physicalAddress] >> 4);
    }

    for(i=0; i<8; i++) {
	USBEndpoint *end16a = [interrupt16EDList objectAt:2*i];
	USBEndpoint *end16b = [interrupt16EDList objectAt:2*i+1];
	USBEndpoint *end08 = [interrupt08EDList objectAt:i];

	/* Set kernel pointers */
	[end16a nextEndpoint:end08];
	[end16b nextEndpoint:end08];
	[end08 prevEndpoint:end16a];

	/* Set physical pointer */
	[end16a descriptor]->dword3.field.nextED = ([end08 physicalAddress] >> 4);
	[end16b descriptor]->dword3.field.nextED = ([end08 physicalAddress] >> 4);
    }

    for(i=0; i<4; i++) {
	USBEndpoint *end08a = [interrupt08EDList objectAt:2*i];
	USBEndpoint *end08b = [interrupt08EDList objectAt:2*i+1];
	USBEndpoint *end04 = [interrupt04EDList objectAt:i];

	/* Set kernel pointers */
	[end08a nextEndpoint:end04];
	[end08b nextEndpoint:end04];
	[end04 prevEndpoint:end08a];

	/* Set physical pointer */
	[end08a descriptor]->dword3.field.nextED = ([end04 physicalAddress] >> 4);
	[end08b descriptor]->dword3.field.nextED = ([end04 physicalAddress] >> 4);
    }

    for(i=0; i<2; i++) {
	USBEndpoint *end04a = [interrupt04EDList objectAt:2*i];
	USBEndpoint *end04b = [interrupt04EDList objectAt:2*i+1];
	USBEndpoint *end02 = [interrupt02EDList objectAt:i];

	/* Set kernel pointers */
	[end04a nextEndpoint:end02];
	[end04b nextEndpoint:end02];
	[end02 prevEndpoint:end04a];

	/* Set physical pointer */
	[end04a descriptor]->dword3.field.nextED = ([end02 physicalAddress] >> 4);
	[end04b descriptor]->dword3.field.nextED = ([end02 physicalAddress] >> 4);
    }

    for(i=0; i<1; i++) {
	USBEndpoint *end02a = [interrupt02EDList objectAt:2*i];
	USBEndpoint *end02b = [interrupt02EDList objectAt:2*i+1];
	USBEndpoint *end01 = [interrupt01EDList objectAt:i];

	/* Set kernel pointers */
	[end02a nextEndpoint:end01];
	[end02b nextEndpoint:end01];
	[end01 prevEndpoint:end02a];

	/* Set physical pointer */
	[end02a descriptor]->dword3.field.nextED = ([end01 physicalAddress] >> 4);
	[end02b descriptor]->dword3.field.nextED = ([end01 physicalAddress] >> 4);
    }

    return self;
}


- (unsigned int)initIRQFromDeviceDescription:(id)deviceDescription
{
    unsigned long irqLine;
    IOReturn irtn;
    unsigned long irqReg,irqData;

    /* Set interrupt line on PCI side */
    irqLine = [deviceDescription interrupt];

    irtn = [deviceDescription setInterruptList:(int *)&irqLine num:1];
    if(irtn) {
	IOLog("usb -  Can't set USB Interrupt Line to IRQ %ld\n",irqLine);
	IOSleep(100);
	return -1;
    }


    /* Read PCI Interrupt Line Register */
    if(irtn = [IODirectDevice getPCIConfigData:&irqReg
			      atRegister:PCI_IRQ_LINE
			      withDeviceDescription:deviceDescription]) {
	IOLog("usb -  Can't read configuration base register 0x3C\n");
	IOSleep(100);
	return -1;
    }


    /* Now set the interrupt byte to the proper value */
    irqReg &= 0xFFFFFF00;
    irqReg |= irqLine;


    /* Set Interrupt Register on PCI card */
    if(irtn = [IODirectDevice setPCIConfigData:irqLine
			            atRegister:PCI_IRQ_LINE
			 withDeviceDescription:deviceDescription]) {
	IOLog("usb -  Can't write PCI Interrupt Enable register 0x3C\n");
	IOSleep(100);
	return -1;
    }


    /* Set edge mode interrupts on PCI */
    if(irtn = [IODirectDevice getPCIConfigData:&irqReg
                                    atRegister:PCI_IRQ_ASGN_REG
                        withDeviceDescription:deviceDescription]) {
	IOLog("usb -  Can't read FireLink Interrupt Assignment register 0x51\n");
	IOSleep(100);
        return -1;
    }


    /* Set Interrupt enable bits for Edge Type IRQ, pg 22 OPTi hardware manual */
    irqReg &= 0xFFFF00FF;
    irqData = (IRQ_TYPE_FS | irqLine | 0x10) << 8;
    irqReg |= irqData;

    /* Put the value into PCI register */
    if(irtn = [IODirectDevice setPCIConfigData:irqReg
			            atRegister:PCI_IRQ_ASGN_REG
			 withDeviceDescription:deviceDescription]) {
	IOLog("usb -  Can't write FireLink Interrupt Assignment register 0x51\n");
	IOSleep(100);
	return -1;
    }

    return irqLine;
}


/*
 *  This is the method that resets the hardware, initializes
 *  the hardware registers with the shared memory physical
 *  address of the Endpoint Descriptors, and turns on the
 *  USB heartbeat (SOH packet generation).
 */

- startHardware
{
    int i,iwait;
    unsigned int  controlReg;
    unsigned int  periodValue,maxPacket;
    unsigned int  status;
    unsigned int  physControlHead,physBulkHead;

    /*  Now - reset controller and initialize its registers */
    *((unsigned int *)(HcBase+HcControl)) = HC_FS_RESET;
    IOSleep(100);

    /*  Perform a Host Controller Reset command */
    *((unsigned int *)(HcBase+HcCommandStatus)) = HC_HCR;
    for(iwait=0; iwait<20; iwait++) {
	IODelay(10);
	status = (*((unsigned int *)(HcBase+HcCommandStatus))) & HC_HCR;
	if(!status) break;
    }

    if(status) {
	IOLog("usb -  TIMEOUT ERROR Resetting Host Controller\n");
	IOSleep(100);
    }

    /* We're now in SUSPEND mode.  We have 2ms to complete initialization */

    *((unsigned int *)(HcBase + HcHCCA)) = physicalHCCABufferBase;

    /* Set HcPeriodicStart to have a value of 90% of the FrameInterval field of HcFmInterval */
    periodValue = FRAME_INTERVAL * 9 / 10;
    *((unsigned int *)(HcBase+HcPeriodicStart)) = periodValue;

    /* This value is calculated like this in both the Linux and BSD drivers */
    maxPacket = ((FRAME_INTERVAL - 210) * 6 / 7) << 16;
    *((unsigned int *)(HcBase+HcFmInterval)) = maxPacket | FRAME_INTERVAL;

    *((unsigned int *)(HcBase+HcLSThreshold)) = 1576;

    /* Set ED Head registers here */
    physControlHead = [[controlEDList objectAt:0] physicalAddress];
    *((unsigned int *)(HcBase + HcControlHeadED)) = (unsigned int)physControlHead;

    physBulkHead = [[bulkEDList objectAt:0] physicalAddress];
    *((unsigned int *)(HcBase + HcBulkHeadED)) = (unsigned int)physBulkHead;

    /*
     *  Fill Interrupt registers in HCCA area with place-holder EDs
     *  from the 32ms interrupt list.
     */
    for(i=0; i<16; i++) {
	*((unsigned int *)(hccaBufferBase+4*balance[i])) =
	    [(USBEndpoint *)[interrupt32EDList objectAt:2*i] physicalAddress];

	*((unsigned int *)(hccaBufferBase+4*(16+balance[i]))) =
	    [(USBEndpoint *)[interrupt32EDList objectAt:2*i+1] physicalAddress];
    }

    /* Disable USB interrupts till we're ready */
    *((unsigned int *)(HcBase+HcInterruptDisable)) = HC_ALL_INTRS;
    
    /* Clear the interrupt status port */
    *((unsigned int *)(HcBase+HcInterruptStatus)) = HC_ALL_INTRS;
    
    /* Set proper List Processing mask and Operational bits in Control Register */
    controlReg = *((unsigned int *)(HcBase+HcControl));
    controlReg &= ~(HC_CBSR_MASK | HC_LES | HC_FS_MASK | HC_IR);
    controlReg |= HC_PLE | HC_IE | HC_CLE | HC_BLE | HC_RATIO_1_4 | HC_FS_OPERATIONAL;

    /*  Start that puppy up!!!   */
    *((unsigned int *)(HcBase+HcControl)) = controlReg;
    IODelay(10);

    /* Done */

    return self;
}


/*
 *  This method sets hardware flags to enable individual
 *  Port Power Enable/Disable
 *
 */

- (void)initPortPower
{
    unsigned int descAValue;

    /* Set individual port power control, See OHCI Spec page 124 */
    descAValue = *((unsigned int *)(HcBase+HcRhDescriptorA));

    /* Assign value to proper bits */
    descAValue |= HC_PSM;
    descAValue &= ~(HC_NPS);

    /* Write value to register */
    *((unsigned int *)(HcBase+HcRhDescriptorA)) = descAValue;
    
    return;
}


- (void)initRootHubConfiguration
{
    unsigned int descAValue,descBValue;

    descAValue = *((unsigned int *)(HcBase+HcRhDescriptorA));
    
    numDownstreamPorts = HC_GET_NDP(descAValue);

    powerSwitchSupported = !(descAValue & HC_NPS);
    if(powerSwitchSupported) powerSwitchingMode = descAValue & HC_PSM;
    else powerSwitchingMode = 0;

    overCurrentProtection = !(descAValue & HC_NOOCP);
    if(overCurrentProtection) overCurrentMode = descAValue & HC_OCPM;
    else overCurrentMode = 0;

    /* Power-On To Power Good Time in ms */
    powerOnDelay = 2*HC_GET_POTPGT(descAValue);


    /* Set Individual Port Power Control mask for all downstream ports */
    descBValue = *((unsigned int *)(HcBase+HcRhDescriptorB));
    descBValue |= 0xFFFF0000;

    /* Write value to register */
    *((unsigned int *)(HcBase+HcRhDescriptorB)) = descBValue;

    return;
}
    



- enumerateDevices
{
    int iport;

    /* Enable Power on each downstream port and check for devices */
    for(iport=1; iport<=numDownstreamPorts; iport++) {

        /* Set Port Power */
        *((unsigned int *)(HcBase+HcRhPortStatus(iport))) = HC_SPP;

	/* Wait 10 ms */
	IOSleep(10);

	/* Determine whether a device is attached */
	if([self deviceOnPort:iport]) {
	    IOSleep(100);
	    [self installDeviceOnPort:iport];
	}

	/* Clear Connect status change bit */
	*((unsigned int *)(HcBase+HcRhPortStatus(iport))) = HC_CSC;
    }
    
    return self;
}




- (int)installDeviceOnPort:(int)devPort
{
    unsigned int powerStat;
    USBDevice *newDevice;
    USBEndpoint *controlEndpoint;
    standardRequest_t devRequest;
    unsigned int usbAddress;
    int devSpeed;
    unsigned char *reqData;
    int i,idev,ndevs;
    int usberr;
    int productIndex;
    char *productDesc;
    int nconfigs,maxPacketSize;
    int configSize,configValue;
    int ninterfaces,maxPower;
    int interfaceOffset, endpointOffset;
    int deviceClass, deviceSubClass;
    int iendpoint,nendpoints;
    BOOL isOldDevice;

    if((devPort < 1) || (devPort > numDownstreamPorts)) {
        IOLog("usb - install port %d out of range.  Must be between 1 and %d\n",
	      devPort,numDownstreamPorts);
	return -1;
    }

    /* Query Port Power Status */
    powerStat = *((unsigned int *)(HcBase+HcRhPortStatus(devPort)));
    powerStat = ((powerStat & HC_PPS) == HC_PPS);

    if(powerStat == OFF) {
        /* Set Port Power */
        *((unsigned int *)(HcBase+HcRhPortStatus(devPort))) = HC_SPP;

	/* Wait 3 ms */
	IOSleep(3);
    }

    /* Make sure there really is a device here */
    if([self deviceOnPort:devPort] == NO) {
        IOLog("usb - No device on port %d\n",devPort);
	return -1;
    }

    /* Enable Port */
    *((unsigned int *)(HcBase+HcRhPortStatus(devPort))) = HC_SPE;
    IOSleep(2);

    /* Reset port, HC_SPR is Host Controller Set Port Reset  */
    [self resetPort:devPort];
    IOSleep(10);

    /*
     *   Now allocate new device with default control descriptor and
     *   dummy Transfer Descriptor, all packaged and ready to go
     *
     */
    newDevice = [[USBDevice alloc] init];
    controlEndpoint = [newDevice controlEndpoint];

    [usbDeviceList addObject:newDevice];
    usbAddress = [usbDeviceList count];

    /* We'll need this later for initializing device endpoints */
    devSpeed = [self deviceSpeed:devPort];


    /* Attach the default control ED to the hardware
     * and to USB ED List 
     */
    [self appendEndpoint:controlEndpoint to:controlEDList];


    /* Clear out any pending halt condition on control endpoint */
    devRequest.bmRequestType = UT_WRITE_ENDPOINT;
    devRequest.bRequest = UR_CLEAR_FEATURE;
    devRequest.wValue.word = UF_ENDPOINT_HALT;
    devRequest.wIndex = 0;
    devRequest.wLength = 0;

    usberr = [self doRequestOnAddress:0
		             endpoint:0
		              request:&devRequest 
                                 data:NULL 
	       	              timeOut:0
                                 from:self];

    if(usberr != 0) {
        IOLog("usb - can't clear possible endpoint halt condition\n");
        return -1;
    }


    /* Get a device descriptor as described on page 239 USB Book */
    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = 0;
    devRequest.wValue.field.high = DEVICE_DESC;
    devRequest.wIndex = 0;
    devRequest.wLength = DV_DESC_LENGTH;

    reqData = IOMalloc(DV_DESC_LENGTH);
    if(reqData == NULL) {
        IOLog("usb -  Kernel error allocating memory buffer for Device Descriptor\n");
	[usbDeviceList removeObject:newDevice];
        [newDevice free];

	return -1;
    }
    for(i=0; i<DV_DESC_LENGTH; i++) reqData[i] = 0;

    /*  Condition locks will wait here until request honored.
     *  While I've tried to implement error checking and time-outs,
     *  the fact is, if something goes wrong during -any- of
     *  the subsequent calls to doRequestOnAddress:  you'll hang.
     *
     *  Drat!
     */
    usberr = [self doRequestOnAddress:0 
		             endpoint:0 
	                      request:&devRequest
	                         data:reqData 
		              timeOut:0
                                 from:self];
    
    if(usberr != 0) {
        IOLog("usb - can't get device descriptor, error %d\n",usberr);
	[usbDeviceList removeObject:newDevice];
        [newDevice free];

	return -1;
    }
    

#if 0
    /* We'll take this out for now, it's a frill we don't need */
    productIndex = ((deviceDescriptor_t *)reqData)->productIndex;
    productDesc = NULL;
    
    if(productIndex > 0)
	productDesc = [self getStringDescriptor:(int)productIndex 
			                      fromUsb:0 atEndpoint:0];

    if((productDesc != NULL) && (strlen(productDesc) > 0))
      [newDevice description:productDesc];

    free(productDesc);
#endif

    /* Get number of configurations for this device */
    nconfigs = ((deviceDescriptor_t *)reqData)->numConfigs;

    /* Set maximum packet size for this control endpoint */
    maxPacketSize = ((deviceDescriptor_t *)reqData)->maxPacketSize;
    [controlEndpoint setMaxPacketSize:maxPacketSize];


    /* Query device for Short Configuration Descriptor */
    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = 0;
    devRequest.wValue.field.high = CONFIG_DESC;
    devRequest.wIndex = 0;
    devRequest.wLength = CF_DESC_LENGTH;

    IOFree(reqData,DV_DESC_LENGTH);
    reqData = IOMalloc(CF_DESC_LENGTH);
    for(i=0; i<CF_DESC_LENGTH; i++) reqData[i] = 0;

    usberr = [self doRequestOnAddress:0
		             endpoint:0 
	                      request:&devRequest
	                         data:reqData
		              timeOut:0
                                 from:self];

    if(usberr != 0) {
        IOLog("usb - can't get config descriptor, error %d\n",usberr);
	[usbDeviceList removeObject:newDevice];
        [newDevice free];

	return -1;
    }

    configSize = ((configDescriptor_t *)reqData)->totalLength;


    /*
     *  Query device for Long Configuration Descriptor, with all
     *  associated interface and endpoint Descriptors.
     *
     */

    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = 0;
    devRequest.wValue.field.high = CONFIG_DESC;
    devRequest.wIndex = 0;
    devRequest.wLength = configSize;

    IOFree(reqData,CF_DESC_LENGTH);
    reqData = IOMalloc(configSize);
    for(i=0; i<configSize; i++) reqData[i] = 0;

    usberr = [self doRequestOnAddress:0
		             endpoint:0 
	                      request:&devRequest
	                         data:reqData
		              timeOut:0
                                 from:self];

    if(usberr != 0) {
        IOLog("usb - can't get long config descriptor, error %d\n",usberr);
	[usbDeviceList removeObject:newDevice];
        [newDevice free];

	return -1;
    }

    ninterfaces = ((configDescriptor_t *)reqData)->numInterfaces;
    maxPower = ((configDescriptor_t *)reqData)->maxPower;

    /*
     *  NOTE:  Someday you should actually do power management
     *         and check whether adding this device would exceed
     *         maximum current available
     */


    configValue = ((configDescriptor_t *)reqData)->configValue;

    interfaceOffset = ((configDescriptor_t *)reqData)->length;
    endpointOffset = interfaceOffset + reqData[interfaceOffset];

    /*  Get number of endpoints */
    nendpoints = ((interfaceDescriptor_t *)(reqData+interfaceOffset))->numEndpoints;

    /*  Get Interface Class  */
    deviceClass = ((interfaceDescriptor_t *)(reqData+interfaceOffset))->class;
    deviceSubClass = ((interfaceDescriptor_t *)(reqData+interfaceOffset))->subClass;

    /* Set USBDevice class */
    [newDevice setUsbClass:deviceClass];
    [newDevice setUsbSubClass:deviceSubClass];


    /************   CHECK IF PREVIOUSLY INSTALLED *************
     *
     *  At this point we have enough information to determine
     *  if this device has been installed previously.  If it
     *  has, free up the resources you allocated above, and
     *  re-activate the device.  Otherwise, install normally.
     *
     */

    isOldDevice = NO;

    ndevs = [usbDeviceList count]-1;
    for(idev=0; idev<ndevs; idev++) {
        USBDevice *localDev = [usbDeviceList objectAt:idev];
	if([localDev hardwareIsUp] == YES) continue;
	if([localDev usbClass] != deviceClass) continue;
	if([localDev usbSubClass] != deviceSubClass) continue;

	if(([localDev description] != NULL) && ([newDevice description] != NULL)) {
	    if(strcmp([localDev description], [newDevice description]) > 0)
	      continue;
	    else {
	      isOldDevice = YES;
	      break;
	    }
	}
	else {
	  isOldDevice = YES;
	  break;
	}
    }

    if(isOldDevice == YES) {
        USBDevice *oldDevice = [usbDeviceList objectAt:idev];
        int oldAddress = [oldDevice usbAddress];

	/* Restore hardware device's usbAddress */
	devRequest.bmRequestType = UT_WRITE_DEVICE;
	devRequest.bRequest = UR_SET_ADDRESS;
	devRequest.wValue.word = oldAddress;
	devRequest.wIndex = 0;
	devRequest.wLength = 0;
    
	usberr = [self doRequestOnAddress:0 
		                 endpoint:0 
	                          request:&devRequest
	                             data:NULL
		                  timeOut:0
                                     from:self];

	if(usberr != 0) {
	    IOLog("usb - can't restore usb address, error %d\n",usberr);
	    return -1;
	}

	/* Give device some time to recover */
	IOSleep(50);

	/* Re-activate old device */
	[self activateDevice:oldDevice];

	/* Set hardware port number */
	[oldDevice hardwareHubPort:devPort];

#if 0
	/* Remove current control endpoint from chain */
	IOLog("Removing redundant endpoint\n");
	[self removeLastEndpointFrom:controlEDList];

	/* Remove and free current device from usb device list */
	IOLog("Removing device from list \n");
	[usbDeviceList removeObject:newDevice];
	[newDevice free];
#else
	/*
	 *  NOTE:   The code above crashes my system hard.  And I've
	 *          tried about everything known to man to cure whatever
	 *          the problem is.  No luck.  So, I'm just going to leave
	 *          the useless node in the chain and set the device's
	 *          parameters to impossible values so it simply can't be
	 *          accessed.
	 *
	 *  Drat!
	 */
	[newDevice usbAddress:127];
	[newDevice hasDeviceDriver:YES];
	[newDevice hardwareIsUp:YES];
	[newDevice hardwareHubPort:999];
	[newDevice setUsbClass:99999];
	[newDevice setUsbSubClass:99999];
	[newDevice deviceDriver:nil];
#endif

	/* Check for a HALTED pipe? */

        return 0;
    }


    /* Set USB Address for this Device, see page 236 USB Book */

    devRequest.bmRequestType = UT_WRITE_DEVICE;
    devRequest.bRequest = UR_SET_ADDRESS;
    devRequest.wValue.word = usbAddress;
    devRequest.wIndex = 0;
    devRequest.wLength = 0;
    
    usberr = [self doRequestOnAddress:0 
		             endpoint:0 
	                      request:&devRequest
	                         data:NULL
		              timeOut:0
                                 from:self];

    if(usberr != 0) {
        IOLog("usb - can't set usb address, error %d\n",usberr);
	[usbDeviceList removeObject:newDevice];
        [newDevice free];

	return -1;
    }

    /* Give device some time to recover */
    IOSleep(50);

    /* Now set new address in the driver object */
    [newDevice usbAddress:usbAddress];


    /*
     *  For each endpoint in the Device:
     *      o  Create an endpoint and add to logical USBDevice
     *      o  Initialize the endpoint parameters
     *      o  Add endpoint to the queue indicated in its descriptor
     */

    for(iendpoint=0; iendpoint<nendpoints; iendpoint++) {
	USBEndpoint *newEndpoint = [[USBEndpoint alloc] init];
	USBTransfer *blankTransfer = [[USBTransfer alloc] init];
	unsigned int endpointAddress = reqData[endpointOffset + 2] & 0x0F;
	unsigned int endpointDir = reqData[endpointOffset + 2] & 0x80;
	unsigned int endpointQueue = reqData[endpointOffset + 3] & 0x03;
	unsigned int endpointMaxPacket = *((unsigned short *)&reqData[endpointOffset + 4]);
	unsigned int interruptInterval = reqData[endpointOffset + 6];

	if(endpointDir == 0) endpointDir = DIR_OUT;
	else endpointDir = DIR_IN;

	/* Queue up a blank Transfer Descriptor */
	[newEndpoint queueTransfer:blankTransfer];

	/* Add the endpoint to the device */
	[newDevice addEndpoint:newEndpoint];

	/* Initialize endpoint parameters */
	[newEndpoint setUsbAddress:usbAddress];
	[newEndpoint setEndpointAddress:endpointAddress];
	[newEndpoint setSpeed:devSpeed];
	[newEndpoint setMaxPacketSize:endpointMaxPacket];

	/* Add the endpoint to the proper Hardware Queue */
	switch(endpointQueue) {
	  case 0:  
	    /* Add endpoint to Control Queue */
	    [newEndpoint setEndpointFormat:0];
	    [newEndpoint setEndpointDir:0];
	    [newEndpoint type:CONTROL_TYPE];
	    [self appendEndpoint:newEndpoint to:controlEDList];
	    break;

	  case 1:
	    /* Add endpoint to Isochronous Queue */
	    [newEndpoint setEndpointFormat:1];
	    [newEndpoint setEndpointDir:endpointDir];
	    [newEndpoint type:ISOCHRONOUS_TYPE];
	    IOLog("usb - isochronous endpoint detected.\n");
	    IOLog("      This is not supported yet\n");
#if 0
	    /* Isochronous endpoints not supported yet */
	    [self appendEndpoint:newEndpoint to:isochronousEDList];
#endif
	    break;

	  case 2:
	    /* Add endpoint to Bulk Queue */
	    [newEndpoint setEndpointFormat:0];
	    [newEndpoint setEndpointDir:endpointDir];
	    [newEndpoint type:BULK_TYPE];
	    [self appendEndpoint:newEndpoint to:bulkEDList];
	    break;

	  case 3:
	    /* Add endpoint to Interrupt Queue */
	    [newEndpoint setEndpointFormat:0];
	    [newEndpoint setEndpointDir:endpointDir];
	    [newEndpoint type:INTERRUPT_TYPE];

	    [self insertInterruptEndpoint:newEndpoint atInterval:(int)interruptInterval];

	    break;

	  default:
	    /*  Unknown Queue type */
	    break;
	}

	endpointOffset += reqData[endpointOffset];
    }
    
    IOFree(reqData, configSize);


    /*          ******  THIS HARDWARE IS NOW OPERATIONAL  ******            */

    [newDevice hardwareIsUp:YES];
    [newDevice hubAddress:0];                /* Connected to Root hub       */
    [newDevice hardwareHubPort:devPort];     /* Needed in case disconnected */

    return 0;
}    





- (void)idleDeviceOnPort:(int)portnum
{
    USBDevice *device;
    int idev, ndevs;

    /* Find out which device is on this port */
    ndevs = [usbDeviceList count];
    for(idev=0; idev<ndevs; idev++) {
      device = [usbDeviceList objectAt:idev];
      if([device hardwareHubPort] == portnum)
	break;
    }
    
    if(idev >= ndevs) return;

    /* Mark the device as not up */
    [device hardwareIsUp:NO];

    /* Disable endpoints */
    [device idleEndpoints];

    /* Done */
    return;
}


- (void)activateDevice:(USBDevice *)device
{
    /* Enable endpoints */
    [device activateEndpoints];

    /* Mark device as up */
    [device hardwareIsUp:YES];

    /* Done */
    return;
}

    
- (void)ignoreRHSC:(BOOL)flag
{
    ignoreRHSC = flag;
}


/*
 *  NOTE:  The data field of the deviceRequest inside the
 *         transfer request --MUST-- --MUST-- be wired
 *         kernel memory.
 */

- (int)deviceRequest:(TransferRequest *)transRequest
{
    standardRequest_t *devRequest;
    USBEndpoint *endpoint;
    unsigned char *reqData;
    unsigned int packetDir;
    unsigned int maxPacketSize;
    USBTransfer *setupTransfer,*statusTransfer,*dataTransfer;
    USBTransfer *tailTransfer;
    volatile td_t *setupTD,*statusTD,*dataTD = NULL;
    unsigned char *setupData;
    int numFullTDs=0, numDataTDs=0, numExtras=0;
    unsigned char *dataPtr;
    unsigned int physDataPtr;
    int ioerr;
    unsigned int status;

    /*
     *  You need to create these transfer descriptors:
     *
     *       1)  Setup Phase
     *       2)  Data Phase  [zero or many of these, depending on transfer]
     *       3)  Status Phase
     *       4)  New Blank TD
     *
     *  Note:  All Hardware-level TDs which are created here will be
     *         queued to an endpoint and processed by the hardware.
     *         When processing is complete, the TDs are moved to the
     *         'done queue' by the hardware.  A 'Write-back Done Head'
     *         interrupt is generated signaling the method -purgeDoneQueue
     *         to dispose of the remains.
     *
     */

    devRequest = [transRequest deviceRequest];
    endpoint = [transRequest endpoint];
    reqData = [transRequest data];

    packetDir = [transRequest dataDir];
    maxPacketSize = [endpoint maxPacketSize];

    /* Get tail transfer object for this endpoint      */
    /* This descriptor will become the setup phase TD  */

    setupTransfer = [endpoint tailTransfer];
    setupTD = [setupTransfer descriptor];

    /* 
     *  As explained on pg 23 of the OHCI Spec, the SETUP TD of a
     *  control transfer has a TOGGLE format of DATA0 (I call that
     *  TOGGLE_0 in this code).  The subsequent data packets alternate
     *  between DATA1 and DATA0 (TOGGLE_1 and TOGGLE_0).  The final
     *  status packet always has a TOGGLE format of DATA1.
     *  
     */

    /* 1)  SETUP TD flags */
    setupTD->dword0.field.undef1 = 0;
    setupTD->dword0.field.bufferRounding = 1;
    setupTD->dword0.field.directionPID = DIR_SETUP;
    setupTD->dword0.field.delayInterrupt = NO_INTERRUPT;
    setupTD->dword0.field.dataToggle = TOGGLE_0;
    setupTD->dword0.field.errorCount = 0;
    setupTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;

    /* Allocate and connect a data buffer with 8 bytes */
    [setupTransfer allocDataPacket:STANDARD_REQ_LENGTH];

    /* Get a handle on the data, fill with standard request */
    setupData = [setupTransfer dataPacket];

    /*
     *  Fill with Standard Request to extract Descriptor Type reqType
     *  as per Pg 235 USB Book
     */
    ((standardRequest_t *)setupData)->bmRequestType = devRequest->bmRequestType;     /*  See page 235, USB Book  */
    ((standardRequest_t *)setupData)->bRequest      = devRequest->bRequest;          /*  See page 239, USB Book  */
    ((standardRequest_t *)setupData)->wValue.word   = devRequest->wValue.word;       /*  Index into descriptor   */
    ((standardRequest_t *)setupData)->wIndex        = devRequest->wIndex;            /*  Language ID             */
    ((standardRequest_t *)setupData)->wLength       = devRequest->wLength;           /*  Length of data returned */

    /*
     *  Put the setup TD in the TransferRequest.  
     *  Notice it's already queued to the ED
     */
    [transRequest addTransfer:setupTransfer];

    if(devRequest->wLength > 0) {
        int idata;
	/*
	 * 2)  Setup some data packet TDs.  No packet if dataLength is ZERO
	 *     More than one may be necessary.
	 */
	
	/* Calculate how many we need */
	numFullTDs = (unsigned int)((devRequest->wLength)/maxPacketSize);
	numExtras = (unsigned int)((devRequest->wLength) % maxPacketSize);
	numDataTDs = numFullTDs + ((numExtras != 0) ? 1 : 0);

	for(dataPtr=reqData,idata=0; idata<numFullTDs; idata++) {
	    dataTransfer = [[USBTransfer alloc] init];
	    dataTD = [dataTransfer descriptor];

	    dataTD->dword0.field.undef1 = 0;
	    dataTD->dword0.field.bufferRounding = 1;                /* Rounding not OK         */
	    dataTD->dword0.field.directionPID = packetDir;          /* Direction of data packs */
	    dataTD->dword0.field.delayInterrupt = NO_INTERRUPT;
	    dataTD->dword0.field.dataToggle = TOGGLE_AUTO;
	    dataTD->dword0.field.errorCount = 0;
	    dataTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;

	    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dataPtr, &physDataPtr);
	    if(ioerr) {
		IOLog("usb - Kernel can't locate physical location of data buffer\n");
		return EIO;
	    }
	    
	    dataTD->dword1.field.currentPointer = physDataPtr;
	    dataTD->dword3.field.bufferEnd = physDataPtr+maxPacketSize-1;
	
	    dataPtr += maxPacketSize;

	    /* Queue the data packet */
	    [transRequest addTransfer:dataTransfer];
	    [endpoint queueTransfer:dataTransfer];
	}

	/* Queue up the last packet, if necessary */
	if(numExtras > 0) {
	    dataTransfer = [[USBTransfer alloc] init];
	    dataTD = [dataTransfer descriptor];

	    dataTD->dword0.field.undef1 = 0;
	    dataTD->dword0.field.bufferRounding = 1;             /* Rounding OK   */
	    dataTD->dword0.field.directionPID = packetDir;       /* Input data    */
	    dataTD->dword0.field.delayInterrupt = NO_INTERRUPT;
	    dataTD->dword0.field.dataToggle = TOGGLE_AUTO;
	    dataTD->dword0.field.errorCount = 0;
	    dataTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;

	    ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dataPtr, &physDataPtr);
	    if(ioerr) {
		IOLog("usb - Kernel can't locate physical location of data buffer\n");
		return EIO;
	    }
	    
	    dataTD->dword1.field.currentPointer = physDataPtr;
	    dataTD->dword3.field.bufferEnd = physDataPtr+numExtras-1;
	
	    dataPtr += numExtras;

	    /* Queue the data packet */
	    [transRequest addTransfer:dataTransfer];
	    [endpoint queueTransfer:dataTransfer];
	}
    }

    /*
     *  3)  Setup a status packet TD
     */
    statusTransfer = [[USBTransfer alloc] init];
    statusTD = [statusTransfer descriptor];
    
    /* Setup transfer descriptor flags */
    statusTD->dword0.field.undef1 = 0;
    statusTD->dword0.field.bufferRounding = 1;               /* Rounding OK      */
    statusTD->dword0.field.directionPID = 
	    (packetDir==DIR_OUT) ? DIR_IN : DIR_OUT;         /* Data OUT - ACK from Device, pg 107 USB Book  */
    statusTD->dword0.field.delayInterrupt = 6;
    statusTD->dword0.field.dataToggle = TOGGLE_1;            /* Status is always TOGGLE_1  */
    statusTD->dword0.field.errorCount = 0;
    statusTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;
    statusTD->dword1.field.currentPointer = 0;
    statusTD->dword3.field.bufferEnd = 0;

    /* Queue the status packet */
    [endpoint queueTransfer:statusTransfer];
    [transRequest addTransfer:statusTransfer];


    /* 
     *  4)  Setup a new empty Tail TD
     */
    tailTransfer = [[USBTransfer alloc] init];
    [endpoint queueTransfer:tailTransfer];


    /* Update the Control Endpoint Tailpointer  */
    [endpoint updateTailPointer];

    /* Let Controller know we've queued something (Control List Filled)  */
    status = *((unsigned int *)(HcBase+HcCommandStatus));
    status |= (HC_CLF | HC_BLF);
    *((unsigned int *)(HcBase+HcCommandStatus)) = status;

    /*
     *  Everything is queued.  Let the hardware do its thing
     *  and fill the data buffers.  Hardware will generate an
     *  interrupt and the kernel will message -interruptOccurred
     *  when data has been transferred.  interruptOccurred then
     *  messages purgeDoneQueue to clean up and unlock the
     *  transferLock with TRANSFER_DONE.
     */

    return 0;
}
    

/*
 *  NOTE:  The data field of the deviceRequest inside the
 *  transfer request --MUST-- --MUST-- be wired kernel memory.
 */

- (int)ioRequest:(TransferRequest *)transRequest
{
    USBEndpoint *endpoint;
    unsigned char *reqData;
    unsigned int packetDir;
    unsigned int maxPacketSize;
    int numFullTDs=0, numDataTDs=0, numExtras=0;
    USBTransfer *dataTransfer;
    USBTransfer *tailTransfer;
    volatile td_t *dataTD = NULL;
    unsigned char *dataPtr;
    unsigned int physDataPtr;
    int idata,ioerr;
    unsigned int status;

    /*
     *  Note:  All Hardware-level TDs which are created here will be
     *         queued to an endpoint and processed by the hardware.
     *         When processing is complete, the TDs are moved to the
     *         'done queue' by the hardware.  A 'Write-back Done Head'
     *         interrupt is generated signaling the method -purgeDoneQueue
     *         to dispose of the remains.
     *
     */

    if([transRequest dataLength] == 0) return 0;

    endpoint = [transRequest endpoint];
    reqData = [transRequest data];

    /* Extract Data direction from Request command */
    packetDir = [transRequest dataDir];
    maxPacketSize = [endpoint maxPacketSize];

    /* Calculate how many we need */
    numFullTDs = (unsigned int)([transRequest dataLength]/maxPacketSize);
    numExtras = (unsigned int)([transRequest dataLength] % maxPacketSize);
    numDataTDs = numFullTDs + ((numExtras != 0) ? 1 : 0);

    for(dataPtr=reqData,idata=0; idata<numFullTDs; idata++) {

	/* The very first TD is the last one on the EDs queue */
	if(idata==0)
	    dataTransfer = [endpoint tailTransfer];
	else
	    dataTransfer = [[USBTransfer alloc] init];

	dataTD = [dataTransfer descriptor];

	dataTD->dword0.field.undef1 = 0;
	dataTD->dword0.field.bufferRounding = 1;
	dataTD->dword0.field.directionPID = packetDir;
	dataTD->dword0.field.delayInterrupt = (idata==0 ? 6 : NO_INTERRUPT);
	if((idata==0) && ([endpoint forceToggle]==YES)) {
	    dataTD->dword0.field.dataToggle = TOGGLE_0;
	    [endpoint forceToggle:NO];
	}
	else
	  dataTD->dword0.field.dataToggle = TOGGLE_AUTO;
	dataTD->dword0.field.errorCount = 0;
	dataTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;

	ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dataPtr, &physDataPtr);
	if(ioerr) {
	  IOLog("usb - Kernel can't locate physical location of data buffer\n");
	  return EIO;
	}
	    
	dataTD->dword1.field.currentPointer = physDataPtr;
	dataTD->dword3.field.bufferEnd = physDataPtr+maxPacketSize-1;
	
	dataPtr += maxPacketSize;

	/* Queue the data packet.  Note the very first one is already queued */
	if(idata > 0)
	  [endpoint queueTransfer:dataTransfer];

	[transRequest addTransfer:dataTransfer];
    }

    /* Queue up the last packet, if necessary */
    if(numExtras > 0) {
	/* If this is the very first TD, dataTransfer is the last one on the EDs queue */
	if(idata==0)
	    dataTransfer = [endpoint tailTransfer];
	else
	    dataTransfer = [[USBTransfer alloc] init];

	dataTD = [dataTransfer descriptor];

	dataTD->dword0.field.undef1 = 0;
	dataTD->dword0.field.bufferRounding = 1;
	dataTD->dword0.field.directionPID = packetDir;
	dataTD->dword0.field.delayInterrupt = NO_INTERRUPT;
	dataTD->dword0.field.dataToggle = TOGGLE_AUTO;
	dataTD->dword0.field.errorCount = 0;
	dataTD->dword0.field.conditionCode = HC_CC_NOT_ACCESSED;

	ioerr = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dataPtr, &physDataPtr);
	if(ioerr) {
	  IOLog("usb - Kernel can't locate physical location of data buffer\n");
	  return EIO;
	}
	    
	dataTD->dword1.field.currentPointer = physDataPtr;
	dataTD->dword3.field.bufferEnd = physDataPtr+numExtras-1;
	
	dataPtr += numExtras;

	/* Queue the data packet.  Note the very first one is already queued */
	if(idata > 0)
	  [endpoint queueTransfer:dataTransfer];

	[transRequest addTransfer:dataTransfer];
    }

    dataTD->dword0.field.delayInterrupt = 6;

    /* Setup a new empty Tail TD  */
    tailTransfer = [[USBTransfer alloc] init];
    [endpoint queueTransfer:tailTransfer];

    /* Update the Control Endpoint Tailpointer  */
    [endpoint updateTailPointer];

    /* Let Controller know we've queued something (Control List Filled)  */
    status = *((unsigned int *)(HcBase+HcCommandStatus));
    status |= (HC_CLF | HC_BLF);
    *((unsigned int *)(HcBase+HcCommandStatus)) = status;

    /*
     *  Everything is queued.  Let the hardware do its thing
     *  and fill the data buffers.  Hardware will generate an
     *  interrupt and the kernel will message -interruptOccurred
     *  when data has been transferred.  interruptOccurred then
     *  messages purgeDoneQueue to clean up and unlock the
     *  transferLock with TRANSFER_DONE.
     */

    return 0;
}
    

- (void)appendEndpoint:(USBEndpoint *)newEndpoint to:(List *)edList
{
    USBEndpoint *tailEndpoint;
    ed_t *tailED,*newED;
    unsigned int newPhysED;

    if([edList count] == 0) {
	/* This should never happen */
	IOLog("usb -  No ED Placeholder in Hardware!\n");
	IOSleep(100);
	return;
    }

    newED = [newEndpoint descriptor];
    newPhysED = [newEndpoint physicalAddress];
    newED->dword0.field.skip = 0;
    newED->dword3.field.nextED = 0;

    /* Get last ED in List */
    tailEndpoint = [edList lastObject];
    tailED = [tailEndpoint descriptor];
    tailED->dword3.field.nextED = (newPhysED >> 4);

    /* Update kernel pointers */
    [tailEndpoint nextEndpoint:newEndpoint];
    [newEndpoint prevEndpoint:tailEndpoint];
    [newEndpoint nextEndpoint:nil];

    /* Append the new Endpoint to the list */
    [edList addObject:newEndpoint];

    return;
}


- (void)removeEndpoint:(USBEndpoint *)thisEndpoint
{
    USBEndpoint *prevEndpoint = [thisEndpoint prevEndpoint];
    USBEndpoint *nextEndpoint = [thisEndpoint nextEndpoint];

    if(prevEndpoint == nil) {
        IOLog("usb - No ED Placeholder in Hardware B!\n");
	return;
    }

#if 0
    [self pauseEndpoint:thisEndpoint];
#else
    {
        [thisEndpoint descriptor]->dword0.field.skip = 1;
	IOSleep(2);
    }
#endif

    if(nextEndpoint != nil) {
        /* Update physical pointer */
        [prevEndpoint descriptor]->dword3.field.nextED = 
	    ([nextEndpoint physicalAddress] >> 4);

	/* Update kernel pointers */
	[prevEndpoint nextEndpoint:nextEndpoint];
	[nextEndpoint prevEndpoint:prevEndpoint];
    }
    else {
        /* Update physical pointer */
        [prevEndpoint descriptor]->dword3.field.nextED = 0;

	/* Update kernel pointers */
	[prevEndpoint nextEndpoint:nil];
    }

    [thisEndpoint descriptor]->dword0.field.skip = 0;

    return;
}
    



- (void)insertInterruptEndpoint:(USBEndpoint *)newED atInterval:(int)intInterval
{
    List *interruptList = nil;
    int i,n;
    USBEndpoint *currentEndpoint = nil;

    /* Determine which interrupt list */
    if(intInterval >= 32) interruptList = interrupt32EDList;
    else if(intInterval >= 16) interruptList = interrupt16EDList;
    else if(intInterval >= 8) interruptList = interrupt08EDList;
    else if(intInterval >= 4) interruptList = interrupt04EDList;
    else if(intInterval >= 2) interruptList = interrupt02EDList;
    else if(intInterval >= 1) interruptList = interrupt02EDList;

    /* Does this endpoint have a valid blank TD? */
    if([newED numTDsQueued] == 0) {
	IOLog("usb - Attempt to insert an interrupt ED without valid blank TD\n");
	return;
    }

    /* Find first empty slot in list */
    n = [interruptList count];
    for(i=0; i<n; i++) {
	currentEndpoint = [interruptList objectAt:i];
	if([[currentEndpoint nextEndpoint] descriptor]->dword0.field.skip == 1)
	    break;
    }

    if(i>=n) {
	IOLog("usb - No available interrupt slots for interval %d\n",intInterval);
	return;
    }

    /* Ah, we found one.  Update the physical pointers */
    [currentEndpoint descriptor]->dword3.field.nextED = ([newED physicalAddress] >> 4);
    [newED descriptor]->dword3.field.nextED = ([[currentEndpoint nextEndpoint] physicalAddress] >> 4);

    /* Update the kernel pointers */
    [newED nextEndpoint:[currentEndpoint nextEndpoint]];
    [newED prevEndpoint:currentEndpoint];

    [[currentEndpoint nextEndpoint] prevEndpoint:newED];
    [currentEndpoint nextEndpoint:newED];

    /* Make sure the skip bit is turned off */
    [newED descriptor]->dword0.field.skip = 0;

    /* I think we're done here */
    return;
}






/****************************   External Interface Protocol  ************************************/


- (BOOL)isUSBHost
{
    return YES;
}

- (BOOL)hardwareIsUp:(int)usbAddress
{
    int idev,ndevs;

    ndevs = [usbDeviceList count];
    for(idev=0; idev<ndevs; idev++) {
	int localAddr = [[usbDeviceList objectAt:idev] usbAddress];
	if(localAddr == usbAddress)
	  return [[usbDeviceList objectAt:idev] hardwareIsUp];
    }

    return NO;
}


- (int)connect:(id)sender toDeviceClass:(int)usbClass subClass:(int)usbSubClass
{
    int idev,ndevs;

    ndevs = [usbDeviceList count];
    for(idev=0; idev<ndevs; idev++) {
	USBDevice *localDev = [usbDeviceList objectAt:idev];
	int iclass = [localDev usbClass];
	int isubclass = [localDev usbSubClass];

	if((iclass != usbClass) || (isubclass != usbSubClass)) continue;

	if( ([localDev hasDeviceDriver] == NO) &&
	    ([localDev hardwareIsUp] == YES) ) {
	        [localDev deviceDriver:sender];
	        return [localDev usbAddress];
	}
    }

    return 0;
}
	    

/*
 *
 *  IMPORTANT NOTE:  reqData absolutely --MUST-- --MUST-- be wired kernel memory.
 *       Also note:  dataDir=0 means data OUT, dataDir=1 means data IN
 */
- (int)doRequestOnAddress:(int)usbAddress 
		 endpoint:(int)endpointNum
                  request:(standardRequest_t *)devReq 
		     data:(unsigned char *)reqData
		  timeOut:(int)hardTimeOut
                     from:(id)sender
{
    int idev,ndevs,dataDir;
    USBDevice *device = nil;
    msg_return_t r;
    USBEndpoint *ep;
    TransferRequest *transRequest;
    static void usbTimeOut(void *);

    /* Get the USBDevice corresponding to this usb address */
    ndevs = [usbDeviceList count];
    for(idev=0; idev<ndevs; idev++) {
	USBDevice *currentDevice = [usbDeviceList objectAt:idev];
	if([currentDevice usbAddress] == usbAddress) {
	    device = currentDevice;
	    break;
	}
    }

    /* Does the device exist */
    if(device == nil) return ENXIO;

    /* insure this is a valid request */
    if((sender != self) && (sender != [device driver])) return EACCES;

    /* insure the hardware is up */
    if([device hardwareIsUp] == NO) return EIO;

    dataDir = (devReq->bmRequestType) & 0x80;
    if(dataDir == 0) dataDir = DIR_OUT;
    else dataDir = DIR_IN;

    /* Set up a TransferRequest for this transaction */
    transRequest = [[TransferRequest alloc] init];
    [transRequest completionCode:HC_CC_NO_ERROR];
    [transRequest device:device];
    [transRequest timeOutPort:msgPort];

    ep = [device endpointForNumber:endpointNum direction:dataDir];
    if(ep == nil) {
	IOLog("UsbOHCI from doRequest:  Can't determine endpoint\n");
	return -1;
    }
    [transRequest endpoint:ep];
    
    /*
     *  Make sure we haven't exceeded the maximum Queue length.
     *  We can spin here till the cows come home, and other
     *  threads still have access to the driver because we
     *  haven't acquired the commandLock yet.  Ah, good!
     */
    while([ep numTDsQueued] > MAXQUEUE) {
	/* Note:  Done Queue is managed by interrupt service
	 *        Otherwise, we'd spin here forever
	 */
	IOSleep(250);
    }

    /*
     *   OK.  Let's get on with business
     */
    [transRequest command:IO_DEVREQ];
    [transRequest deviceRequest:devReq];
    [transRequest data:reqData];
    [transRequest dataLength:devReq->wLength];
    [transRequest dataDir:dataDir];
    [[transRequest transferLock] unlockWith:TRANSFER_INPROGRESS];

    /* Queue the Transfer Request */
    [commandLock lock];

    /*  Make sure we haven't exceeded the maximum Command
     *  Queue Length.  Perhaps commandLock should be an
     *  NXConditionLock?
     */
    while([usbCommandList count] > MAXQUEUE) {
	/* Let someone else in, check later */
	[commandLock unlock];
	IOSleep(250);
	[commandLock lock];
    }

#if 1
    [transRequest expireIn:hardTimeOut];
    if(hardTimeOut > 0)
      IOScheduleFunc(usbTimeOut, transRequest, hardTimeOut);
#else
    [transRequest expireIn:0];
#endif

    [usbCommandList addObject:transRequest];
    [commandLock unlock];


    /*
     *  Tell the IOThread we have work to do.
     *  IOThread gets this message, and sends us back
     *  a 'commandRequestOccurred' message
     *
     */

    r = msg_send_from_kernel(&machMessage, MSG_OPTION_NONE, 0);
    if(r != SEND_SUCCESS) {
	IOLog("usb - Can't send message to I/O thread: %d\n",r);
	return EIO;
    }

    /* Wait till the request is filled */
    [[transRequest transferLock] lockWhen:TRANSFER_DONE];

    /* Dequeue transfer request */
    [processedLock lock];
    [usbProcessedList removeObject:transRequest];
    [processedLock unlock];

    [transRequest free];

    return 0;

}


/*
 *
 *  IMPORTANT NOTE:  reqData absolutely --MUST-- be wired kernel memory
 *      also note that dataDir=0 means data OUT, dataDir=1 means data IN
 */
- (int)doIOonAddress:(int)usbAddress 
	    endpoint:(int)endpointNum  
	   direction:(int)dataDir 
                data:(unsigned char *)reqData 
               ndata:(int)numdata 
	     timeOut:(int)hardTimeOut
		from:(id)sender
{
    int idev,ndevs;
    USBDevice *device = nil;
    msg_return_t r;
    USBEndpoint *ep;
    TransferRequest *transRequest;
    static void usbTimeOut(void *);

    /* Get the USBDevice corresponding to this usb address */
    ndevs = [usbDeviceList count];
    for(idev=0; idev<ndevs; idev++) {
	USBDevice *currentDevice = [usbDeviceList objectAt:idev];
	if([currentDevice usbAddress] == usbAddress) {
	    device = currentDevice;
	    break;
	}
    }

    /* Does the device exist */
    if(device == nil) return ENXIO;

    /* insure this is a valid request */
    if((sender != self) && (sender != [device driver])) return EACCES;

    /* insure the hardware is up */
    if([device hardwareIsUp] == NO) return EIO;

    if(dataDir == 0) dataDir = DIR_OUT;
    else dataDir = DIR_IN;
    
    /* Set up a TransferRequest for this transaction */
    transRequest = [[TransferRequest alloc] init];
    [transRequest completionCode:HC_CC_NO_ERROR];
    [transRequest device:device];

    ep = [device endpointForNumber:endpointNum direction:dataDir];
    if(ep == nil) {
	IOLog("UsbOHCI from doRequest:  Can't determine endpoint\n");
	return -1;
    }
    [transRequest endpoint:ep];
    
    /*
     *  Make sure we haven't exceeded the maximum Endpoint
     *  Queue length.  We can spin here till the cows come
     *  home, and other threads still have access to the driver
     *  because we haven't acquired the commandLock yet.
     */
    while([ep numTDsQueued] > MAXQUEUE) {
	/* Note:  Done Queue is managed by interrupt service
	 *        Otherwise, we'd spin here forever
	 */
	IOSleep(250);
    }

    /*
     *   OK.  Let's get on with business
     */
    [transRequest command:IO_DEVIO];
    [transRequest deviceRequest:NULL];
    [transRequest data:reqData];
    [transRequest dataLength:numdata];
    [transRequest dataDir:dataDir];
    [[transRequest transferLock] unlockWith:TRANSFER_INPROGRESS];

    /* Queue the Transfer Request */
    [commandLock lock];

    /*  Make sure we haven't exceeded the maximum Command
     *  Queue Length.  Perhaps commandLock should be an
     *  NXConditionLock so we don't have to loop?
     */
    while([usbCommandList count] > MAXQUEUE) {
	/* Let someone else in, check later */
	[commandLock unlock];
	IOSleep(250);
	[commandLock lock];
    }

#if 1
    [transRequest expireIn:hardTimeOut];
    if(hardTimeOut > 0) 
      IOScheduleFunc(usbTimeOut, transRequest, hardTimeOut);
#else
    [transRequest expireIn:0];
#endif

    [usbCommandList addObject:transRequest];
    [commandLock unlock];


    /*
     *  Tell the IOThread we have work to do.
     *  IOThread gets this message, and sends us back
     *  a 'commandRequestOccurred' message
     *
     */

    r = msg_send_from_kernel(&machMessage, MSG_OPTION_NONE, 0);
    if(r != SEND_SUCCESS) {
	IOLog("usb - Can't send message to I/O thread: %d\n",r);
	return EIO;
    }

    /* Wait till the request is filled, or until timed out */

    [[transRequest transferLock] lockWhen:TRANSFER_DONE];

    /* Dequeue transfer request */
    [processedLock lock];
    [usbProcessedList removeObject:transRequest];
    [processedLock unlock];

    [transRequest free];

    return 0;

}


- (int)purgeDoneQueue
{
    unsigned int physDoneHead;
    TransferRequest *purgeReq = nil;
    USBEndpoint *purgeEndpoint = nil;
    USBTransfer *purgeTransfer = nil;
    int usberr;
    static void usbTimeOut(void *);

    /* Get first TD on Done Queue Head */
    physDoneHead = *((unsigned int *)(hccaBufferBase + HccaDoneHead));
    physDoneHead &= 0xFFFFFFF0;

    /* If done head is null, get out */
    if(physDoneHead == 0) return 0;

    /* Detach from Hardware Queue */
    *((unsigned int *)(hccaBufferBase + HccaDoneHead)) = 0;

    /* Clear the Interrupt register                       */
    *((unsigned int *)(HcBase+HcInterruptStatus)) = HC_WDH | HC_SF | HC_FNO;

    /* Need access to the TransferRequests in the Processed List */    
    [processedLock lock];

    do {
	int itr,nTRs;

	/*  Find out to which TransferRequest this TD belongs */
	nTRs = [usbProcessedList count];
	for(itr=0; itr<nTRs; itr++) {
	    purgeReq = [usbProcessedList objectAt:itr];
	    purgeTransfer = [purgeReq isTDQueued:physDoneHead];
	    if(purgeTransfer != nil) break;
	}

	if(purgeTransfer == nil) {
	  IOLog("usb - done queue has unknown TD in list: %08x\n",physDoneHead);
	  return -1;
	}

        /* Find next TD in the Done Head Queue */
	physDoneHead = ([purgeTransfer descriptor]->dword2.field.nextTD << 4) & 0xFFFFFFF0;
	purgeEndpoint = [purgeReq endpoint];

	/* Check error status on the TD */
	usberr = [purgeTransfer descriptor]->dword0.field.conditionCode;
	if(usberr != HC_CC_NO_ERROR) {
	    [purgeReq completionCode:usberr];

	    /* If set to expire, cancel it */
	    if([purgeReq expireTime] > 0)
	      IOUnscheduleFunc(usbTimeOut, purgeReq);

	    IOLog("usb - error %d, %s.  HELP!\n",usberr,usberrstr[usberr]);

	    /*   Put this Transfer request in the list to be retired
	     *   Don't double-book Transfer requests!
	     */
	    [errorLock lock];
	    [errorTransferList addObjectIfAbsent:purgeReq];
	    [errorLock unlock];
	}

	/*  
	 *  Now dispose of this TD
	 */

	/* Remove this TD from the TransferRequest */
	[purgeReq removeTransfer:purgeTransfer];

	/*  Remove the TD from the ED list, free up memory.
	 *  This de-allocates all memory associated
	 *  with this TD with no regard to maintaining the
	 *  integrity of the chain.  No need to since it's
	 *  been de-queued from the hardware list by the
	 *  usb controller chip.
	 */
	[purgeEndpoint deQueueTransfer:purgeTransfer];

	/*  If all TD's have been cleared from this TransferRequest,
	 *  we can set unlock it's lock and be free!!
	 */

	if(([purgeReq completionCode] == HC_CC_NO_ERROR) && ([purgeReq numTDsQueued] == 0)) {

	  /* If set to expire, cancel it */
	  if([purgeReq expireTime] > 0)
	      IOUnscheduleFunc(usbTimeOut, purgeReq);

	  /* Notify request is filled */
	  [[purgeReq transferLock] unlockWith:TRANSFER_DONE];

	    /*
	     *  The request is actually removed from the Processed Queue
	     *  by the last two lines of -doRequestOnAddress.
	     *
	     */
	}

    } while(physDoneHead != 0);
    
    [processedLock unlock];


    /* Now purge the errorList */
    [errorLock lock];

    if([errorTransferList count] > 0)
      [plumberLock unlockWith:PLUMBER_NEEDED];

    [errorLock unlock];

    return 0;
}



/*
 *  All Transfer requests which were marked
 *  with errors are handled here.
 *
 *  NOTE:  There's something wrong with this method which
 *         is why there's so many debug prints remaining
 *         in it.  The doRequestonAddress: or doIOonAddress:
 *         which generated the error packets are hanging as
 *         if they are never receiving the TRANSFER_DONE.
 *         Yet clearly the TRANSFER_DONE is being issued.
 *         I don't know why there's a problem.
 *
 *  Drat!
 */


- (void)processErrorTransfers
{
    TransferRequest *purgeReq;
    USBEndpoint *purgeEndpoint;
    USBTransfer *purgeTransfer;
#if 0
    standardRequest_t devRequest;
    int usberr;
#endif
    static void usbTimeOut(void *);

    /*
     *  The plumber is here to clear the pipes.
     *  Time to roll up your sleeves and get dirty.
     */

    IOLog("usb - Processing Error packets\n");

    [errorLock lock];
    while([errorTransferList count] > 0) {
        purgeReq = [errorTransferList objectAt:0];
        purgeEndpoint = [purgeReq endpoint];

	IOLog("   Pausing endpoint \n");

	/* Halt this endpoint */
	[self pauseEndpoint:purgeEndpoint];

        /*  Purge this TransferRequest of all its TD's then
	 *  unlock with TRANSFER_DONE
	 */
	IOLog("   Purging all TDs\n");
        while([purgeReq numTDsQueued] > 0) {
	    purgeTransfer = [purgeReq transferAt:0];
	    [purgeReq removeTransferAt:0];
	    [purgeEndpoint unLinkTransfer:purgeTransfer];
	}
	IOLog("   All TD's removed\n");

	/* Re-enable this endpoint */
	IOLog("   Re-enabling endpoint \n");
	[purgeEndpoint descriptor]->dword0.field.skip = 0;

	/* Remove this Transfer Request from list */
	[errorTransferList removeObject:purgeReq];

	IOLog("   Notify with TRANSFER_DONE\n");
	/* Notify request is terminated */
	[[purgeReq transferLock] unlockWith:TRANSFER_DONE];

	/* 
	 *  This routine is never coming back from the 
	 *  doRequest.  I'm sure this is related to the
	 *  problem mentioned above.
	 */
#if 0
	/* Tell device everything is OK */
	if([purgeEndpoint isHalted]) {

	    [purgeEndpoint descriptor]->dword2.field.halt = 0;
	  
	    /*  First write on a stalled endpoint must
	     *  be with TOGGLE_0
	     */
	    [purgeEndpoint forceToggle:YES];

	    devRequest.bmRequestType = UT_WRITE_ENDPOINT;
	    devRequest.bRequest = UR_CLEAR_FEATURE;
	    devRequest.wValue.word = UF_ENDPOINT_HALT;
	    devRequest.wIndex = [purgeEndpoint endpointAddress];
	    devRequest.wLength = 0;

	    usberr = [self doRequestOnAddress:[purgeEndpoint usbAddress]
                                     endpoint:0
			              request:&devRequest 
                                         data:NULL 
	       	                      timeOut:0
                                         from:self];

	    if(usberr != 0) {
	      IOLog("usb - can't clear Endpoint Halt condition\n");
	      return;
	    }
	}
#endif

    }
    [errorLock unlock];

    return;
}




/*
 *  Note:  This routine is also having problems.  I suppose
 *         that's not surprising since it's nearly identical
 *         to the processErrorTransfers above.  Same symptoms:
 *         calling routine hangs as if it never receives the
 *         TRANSFER_DONE condition.
 *
 *  Drat!
 *
 */


- (void)processTimeouts
{
    TransferRequest *timedRequest;
    USBEndpoint *timedEP;
#if 0
    int usberr;
    standardRequest_t devRequest;
#endif

    IOLog("usb - Processing Timeout packets\n");

    /*
     *  Retire all Transfer Requests in the timeoutList
     */

    [timeLock lock];
    while([timeoutList count] > 0) {
        timedRequest = [timeoutList objectAt:0];
	timedEP = [timedRequest endpoint];

	/* Halt this endpoint */
	IOLog("   Pausing endpoint \n");

	[self pauseEndpoint:timedEP];

	/* Purge this TransferRequest of all its TD's and unlock with TRANSFER_DONE */
	IOLog("   Purging all TDs\n");
	while([timedRequest numTDsQueued] > 0) {
	    USBTransfer *timedTD = [timedRequest transferAt:0];
	    [timedRequest removeTransferAt:0];
	    [timedEP unLinkTransfer:timedTD];
	}

	IOLog("   All TD's removed\n");

	/* Re-enable this endpoint */
	IOLog("    Re-enabling endpoint \n");
	[timedEP descriptor]->dword0.field.skip = 0;

	/* Remove this Transfer Request from the timeout List */
	[timeoutList removeObject:timedRequest];

	IOLog("Notify with TRANSFER_DONE\n");
	/* Notify request is terminated */
	[timedRequest completionCode:CC_EXPIRED];
	[[timedRequest transferLock] unlockWith:TRANSFER_DONE];

#if 0
	/* Tell device everything is OK */
	if([timedEP isHalted]) {

	    [timedEP descriptor]->dword2.field.halt = 0;
	  
	    /*  First write on a stalled endpoint must
	     *  be with TOGGLE_0
	     */
	    [timedEP forceToggle:YES];

	    devRequest.bmRequestType = UT_WRITE_ENDPOINT;
	    devRequest.bRequest = UR_CLEAR_FEATURE;
	    devRequest.wValue.word = UF_ENDPOINT_HALT;
	    devRequest.wIndex = [timedEP endpointAddress];
	    devRequest.wLength = 0;

	    usberr = [self doRequestOnAddress:[timedEP usbAddress]
                                     endpoint:0
			              request:&devRequest 
                                         data:NULL 
	       	                      timeOut:0
                                         from:self];

	    if(usberr != 0) {
	      IOLog("usb - can't clear Endpoint Halt condition\n");
	    }
	}
#endif

    }

    [timeLock unlock];

    IOLog("process timeouts done\n");
    return;
}



/*
 *  Page 59 of OHCI Spec sheets describe the procedure to pause
 *  an endpoint.  I don't follow their procedure exactly, and this
 *  routine is suspect.
 */

- (void)pauseEndpoint:(USBEndpoint *)endPoint
{
    unsigned int control;
    unsigned int enableFlags = 0;
    unsigned int currentEDRegister =0;

    /* Set skip bit */
    [endPoint descriptor]->dword0.field.skip = 1;
    
    /* Wait a frame time */
    IOSleep(2);

    if([endPoint type] == BULK_TYPE) {
        enableFlags = HC_BLE;
	currentEDRegister = HcBulkCurrentED;
    }
    else if([endPoint type] == CONTROL_TYPE) {
        enableFlags = HC_CLE;
	currentEDRegister = HcBulkCurrentED;
    }


    /* Disable processing control list */
    control = *((unsigned int *)(HcBase+HcControl));
    control &= ~enableFlags;
    *((unsigned int *)(HcBase+HcControl)) = control;

    /* Give it time to finish current frame */
    IOSleep(2);

    /* Force controller off the currentED list */
    *((unsigned int *)(HcBase+currentEDRegister)) = 0;

    /* Re-enable processing ED list */
    control = *((unsigned int *)(HcBase+HcControl));
    control |= enableFlags;
    *((unsigned int *)(HcBase+HcControl)) = control;

    /*  At this point, the endpoint should be paused,
     *  and the host controller should not be accessing
     *  it or any of its transfer descriptors.
     */

    return;
}



- (char *)getStringDescriptor:(int)sindex fromUsb:(int)usbAddress atEndpoint:(int)endpoint
{
    standardRequest_t devRequest;
    unsigned int reqLength,strLength;
    unsigned char *reqData;
    unsigned char *result;
    int i,usberr;
    unsigned short langID;

    if(sindex==0) return NULL;

    /* First, get the language ID */
    reqLength = 4;

    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = 0;
    devRequest.wValue.field.high = STRING_DESC;
    devRequest.wIndex = 0;
    devRequest.wLength = reqLength;

    reqData = IOMalloc(reqLength);
    if(reqData == NULL) {
	IOLog("usb - Kernel error allocating memory buffer for String Descriptor\n");
	return NULL;
    }
    
    for(i=0; i<reqLength; i++) reqData[i] = 0;

    usberr = [self doRequestOnAddress:usbAddress   
                             endpoint:endpoint
		              request:&devRequest 
                                 data:reqData 
			      timeOut:0
                                 from:self];

    if(usberr != 0) {
	IOFree(reqData, reqLength);
	return NULL;
    }

    langID = *((unsigned short *)(reqData + 2));

    /* Now, get the length of the desired string */
    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = sindex;
    devRequest.wValue.field.high = STRING_DESC;
    devRequest.wIndex = langID;
    devRequest.wLength = reqLength;

    for(i=0; i<reqLength; i++) reqData[i] = 0;

    usberr = [self doRequestOnAddress:usbAddress  
                             endpoint:endpoint
		              request:&devRequest 
                                 data:reqData 
	                      timeOut:0
                                 from:self];

    if(usberr != 0) {
	IOFree(reqData, reqLength);
	return NULL;
    }

    strLength = reqData[0];

    IOFree(reqData, reqLength);

    /* Now, get the string */
    reqData = IOMalloc(strLength);
    if(reqData == NULL) {
	IOLog("usb - Kernel error allocating memory buffer for Device String\n");
	return NULL;
    }
    
    for(i=0; i<strLength; i++) reqData[i] = 0;

    devRequest.bmRequestType = UT_READ_DEVICE;
    devRequest.bRequest = UR_GET_DESCRIPTOR;
    devRequest.wValue.field.low = sindex;
    devRequest.wValue.field.high = STRING_DESC;
    devRequest.wIndex = langID;
    devRequest.wLength = strLength-1;

    for(i=0; i<strLength; i++) reqData[i] = 0;

    usberr = [self doRequestOnAddress:usbAddress  
                             endpoint:endpoint
		              request:&devRequest 
                                 data:reqData 
			      timeOut:0
                                 from:self];

    if(usberr != 0) {
	IOFree(reqData, strLength);
	return NULL;
    }

    /* Convert to ascii */
    result = (unsigned char *)malloc(2+strLength/2);
    if(result == NULL) {
	IOLog("usb - Kernel error allocating memory buffer for ascii description\n");
	IOFree(reqData, strLength);
	return NULL;
    }
    
    for(i=0; i<(strLength-2)/2; i++) result[i] = reqData[2*i+2];
    result[i] = '\0';

    IOFree(reqData, strLength);

    return result;
}


- (NXConditionLock *)installLock
{
    return installLock;
}


- (NXConditionLock *)plumberLock
{
    return plumberLock;
}


- (NXConditionLock *)timeoutLock
{
    return timeoutLock;
}













/****************       MACH MESSAGING METHODS     ************************/


/*
 *  IMPORTANT NOTE:  
 *   
 *  You can't issue either doRequestOnAddress: or doIOonAddress: while inside
 *  a method invoked directly or indirectly from -interruptOccurred.  While 
 *  -interruptOccurred is running,  interrupts must be disabled.  But if 
 *  interrupts are disabled, no method which invokes a deviceRequest can 
 *  complete.  So if you call such a method, you've hung yourself.  That's 
 *  why we use NXConditionLocks and utility threads to perform device 
 *  installation and both error and time-out flushes.  These functions 
 *  must perform I/O to devices, and can't be called from here.
 *
 */

- (void)interruptOccurred
{
    int iport;
    unsigned int interruptStatus;
    unsigned int portReset, portStatus;

    /* Disable interrupts while we're here */
    *((unsigned int *)(HcBase+HcInterruptDisable)) = HC_MIE;

    interruptStatus = *((unsigned int *)(HcBase+HcInterruptStatus));

    /* Check the Done Queue */
    if((interruptStatus & HC_WDH) == HC_WDH) {
	[self purgeDoneQueue];
    }

    /* Check the root hub */
    if((ignoreRHSC==NO) && (interruptStatus & HC_RHSC)==HC_RHSC) {

	/* Find out what needs servicing */
	for(iport=1; iport<=numDownstreamPorts; iport++) {
	    portReset = 0;
	    portStatus = *((unsigned int *)(HcBase+HcRhPortStatus(iport)));

	    if((portStatus & HC_CSC) == HC_CSC) {
	        BOOL connect = ((portStatus & HC_CCS) == HC_CCS);
		portReset |= HC_CSC;

		if(connect == NO) {
		    IOLog("usb - device disconnect port %d\n",iport);
		    [self idleDeviceOnPort:iport];
		}
		else {
		  /*
		   *  Message the install thread there's something
		   *  to be done.
		   */
		    IOLog("usb - device connect port %d\n",iport);
		    instPort = iport;
		    [installLock unlockWith:INSTALL_NEEDED];
		}
	    }

	    /* Handle Port Enable Status Change */
	    if((portStatus & HC_PESC) == HC_PESC) {
		portReset |= HC_PESC;
#if 0
	        IOLog("Port Enable status change on port %d\n",iport);
#endif
	    }


	    /* Handle Port Suspend Status Change */
	    if((portStatus & HC_PSSC) == HC_PSSC) {
		portReset |= HC_PSSC;
#if 0
	        IOLog("Port Suspend status change on port %d\n",iport);
#endif
	    }

	    /* Handle Port Over Current Indicator Change */
	    if((portStatus & HC_POCIC) == HC_POCIC) {
		portReset |= HC_POCIC;
#if 0
	        IOLog("Port Over Current Indicator change on port %d\n",iport);
#endif
	    }

	    /* Handle Port Reset Status Change */
	    if((portStatus & HC_PRSC) == HC_PRSC) {
		portReset |= HC_PRSC;
#if 0
	        IOLog("Port Reset Status Change on port %d\n",iport);
#endif
	    }

	    *((unsigned int *)(HcBase+HcRhPortStatus(iport))) = portReset;
	}

    }

    /* Clear status bits */
    *((unsigned int *)(HcBase+HcInterruptStatus)) = 0x7F;

    /* Re-enable interrupts on the USB side */
    *((unsigned int *)(HcBase+HcInterruptEnable)) = HC_SO | HC_WDH | HC_RD | HC_UE | HC_RHSC | HC_MIE;

    /* Re-enable interrupts on the PCI side */
    [self enableAllInterrupts];
    return;

}


- (void)commandRequestOccurred
{
    int usberr;
    TransferRequest *transRequest;

    /*  De-Queue a request, process it,
     *  and place on processed list
     */
    [commandLock lock];
    transRequest = [usbCommandList objectAt:0];
    [usbCommandList removeObjectAt:0];
    [commandLock unlock];

    [processedLock lock];
    [usbProcessedList addObject:transRequest];
    [processedLock unlock];

    switch([transRequest command]) {
      case IO_DEVREQ:
	usberr = [self deviceRequest:transRequest];

	/*  Don't unlock transRequest here -
	 *  that's done during interrupt servicing
	 *  when all TD's associated with this request
	 *  have been dequeued
	 */

	break;

      case IO_DEVIO:
	usberr = [self ioRequest:transRequest];
	/*  Again, don't unlock here -
	 *  We issue the unlock when all TD's associated
	 *  with this request have been properly de-queued
	 *  during interrupt servicing
	 */
	break;
	
      default:
	IOLog("usb - unknown device request\n");
	break;
    }

    return;
}


- (void)timeoutOccurred
{
#if 1
    IOLog("usb -  Command Request Occurred\n");
    IOSleep(100);
#endif

    return;
}




- (void) interruptOccurredAt:(int)localInterrupt
{
#if 1
    IOLog("Interrupt At\n");
#endif
    return;
}


- (void)receiveMsg
{
#if 1
    IOLog("usb -  RECEIVEmsg Interrupt received.  Possibly INSTALL??\n");
    [super receiveMsg];
#endif

    return;
}


- (void)otherOccurred:(int)msgID
{
#if 1
    IOLog("usb -  OTHER Interrupt received: %08x\n",msgID);
    IOSleep(100);
#endif

    return;
}








/********************* Mid-level hardware management *********************************/




- (BOOL)deviceOnPort:(int)portnum
{
    unsigned int status;
    BOOL isDevice;

    status = *((unsigned int *)(HcBase+HcRhPortStatus(portnum)));

    /* HC_CCS is Host Controller Current Connect Status bit */
    isDevice = (status & HC_CCS) == HC_CCS;
    return isDevice;
}




- (void)resetPort:(int)portnum
{
    unsigned int status;
    unsigned char count;
    
    /* HC_SPR is Host Controller Set Port Reset  */
    *((unsigned int *)(HcBase+HcRhPortStatus(portnum))) = HC_SPR;

    /* Wait till reset complete, or timeout */
    count=0;
    for(count=0; count<50; count++) {
	IOSleep(2);
	status = *((unsigned int *)(HcBase+HcRhPortStatus(portnum)));

	/* HC_PRS is Host Controller Port Reset Status Change */
	if((status & HC_PRSC)==HC_PRSC) break;
    }

#if 0
    if(count >= 50) {
	IOLog("usb -   ***  ERROR:  Can't reset USB port %d\n",portnum);
	IOSleep(100);
    }
#endif

    /* Clear the Reset Status Change bit */
    *((unsigned int *)(HcBase+HcRhPortStatus(portnum))) = HC_PRSC;
    
    return;
}

    
- (int)deviceSpeed:(int)portnum
{
    unsigned int status;

    status = *((unsigned int *)(HcBase+HcRhPortStatus(portnum)));
    status &= 0x00000200;

    if(status > 0) status = 1;

    return status;
}



- (unsigned int)readPortStatus:(int)portnum
{
    return *((unsigned int *)(HcBase+HcRhPortStatus(portnum)));
}


- (void)writePortStatus:(int)iport value:(unsigned int)value
{
    *((unsigned int *)(HcBase+HcRhPortStatus(iport))) = value;
}


- (List *)timeoutList
{
    return timeoutList;
}


- (NXLock *)timeLock
{
    return timeLock;
}












/***************************  Functions *******************************/


static void plumberdaemon(void *arg)
{
    UsbOHCI *driver = arg;
    NXConditionLock *plumbLock = [driver plumberLock];

    do {
        [plumbLock lockWhen:PLUMBER_NEEDED];
#if 1
	[driver processErrorTransfers];
#endif
	IOLog("   plumberdaemon Done.\n");
	[plumbLock unlockWith:PLUMBER_IDLE];

    } while(1);

    return;
}


static void timeoutdaemon(void *arg)
{
    UsbOHCI *driver = arg;
    NXConditionLock *timeoutLock = [driver timeoutLock];
    
    do {
        [timeoutLock lockWhen:TIMEOUT_FIRED];
	
	IOLog("usb - Retiring Expired packets\n");

	[driver processTimeouts];
	
	IOLog("timeoutdaemon Done\n");
	[timeoutLock unlockWith:TIMEOUT_IDLE];
    } while(1);

    return;
}


static void installdaemon(void *arg)
{
    UsbOHCI *driver = arg;
    NXConditionLock *instLock = [driver installLock];
    int err;

    do {
        [instLock lockWhen:INSTALL_NEEDED];

        if(instPort > 0) {
            IOLog("usb - waiting 2 seconds for device to come ready.");
	    IOSleep(2000);

            err = [driver installDeviceOnPort:instPort];

	    if(err == 0)
	      IOLog("usb - device installed on port %d\n",instPort);
	    else
	      IOLog("usb - device not installed on port %d\n",instPort);

            instPort = 0;
        }

        [instLock unlockWith:INSTALL_IDLE];

    } while(1);

    return;
}



static void usbTimeOut(void *arg) {

    [[ohciDriver timeLock] lock];
    [[ohciDriver timeoutList] addObject:arg];
    [[ohciDriver timeLock] unlock];

    /*  This frees function timeoutdaemon() to
     *  do its work 
     */
    [[ohciDriver timeoutLock] unlockWith:TIMEOUT_FIRED];

    return;
}



static void setIgnoreRHSC(void *arg) {
    UsbOHCI *driver = arg;

    [driver ignoreRHSC:NO];

}


/*****************************  Utility Functions ********************************/

unsigned int asciihex_to_uint(char *ascii_rep)
{
    char digitchar;
    int power,digit;
    unsigned int result;
    int ichar, nchars;
    char char_upper(char);

    nchars = 0;
    ichar = 0;
    while(ascii_rep[ichar++]) nchars++;

    result = 0;

    for(power=0, ichar=nchars-1; ichar>=0; ichar--) {

        digitchar = ascii_rep[ichar];
        if((digitchar <= '9') && (digitchar >= '0')) 
	    digit = (int)(digitchar - 0x30);
        else if((char_upper(digitchar) <= 'F') && (char_upper(digitchar) >= 'A')) 
	    digit = (int)(char_upper(digitchar) - 0x37);
 	else 
	    break;

        result += (digit << power);
        power += 4;
    }
    return result;
}

char char_upper(char inchar)
{
    if(inchar < 0x61) return inchar;
    return inchar - 0x20;
}


@end

