/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#define KERNEL 1

#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/interruptMsg.h>
#import <kernserv/prototypes.h>
#import <machkit/NXLock.h>
#import <sys/errno.h>
#import <string.h>
#import "UsbOHCIInterface.h"
#import "USBDevice.h"
#import "USBEndpoint.h"
#import "USBTransfer.h"
#import "TransferRequest.h"

#define OFF FALSE
#define ON  TRUE

#define CONTROL_TYPE     100
#define BULK_TYPE        200
#define INTERRUPT_TYPE   300
#define ISOCHRONOUS_TYPE 400

#define MAXQUEUE 100

static unsigned char balance[16] = {
    0x0, 0x8, 0x4, 0xC,
    0x2, 0xA, 0x6, 0xE,
    0x1, 0x9, 0x5, 0xD,
    0x3, 0xB, 0x7, 0xF
};
    

/* Valid TransferRequest command values */
#define IO_DEVREQ    100
#define IO_DEVIO     200

/* Valid installLock values */
#define INSTALL_IDLE    400
#define INSTALL_NEEDED  500


/* Valid plumberLock values */
#define PLUMBER_IDLE    600
#define PLUMBER_NEEDED  700


/* Valid timeoutLock values */
#define TIMEOUT_IDLE    800
#define TIMEOUT_FIRED   900


@interface UsbOHCI : IODirectDevice <OHCI_Interface>
{
    /* Hardware Addresses */
    volatile vm_address_t HcBase;
    volatile unsigned int *physicalHcBase;
    vm_address_t hccaBufferFree;
    volatile vm_address_t hccaBufferBase;
    volatile unsigned int physicalHCCABufferBase;

    /* Root Hub configuration */
    unsigned int numDownstreamPorts;
    BOOL powerSwitchSupported;
    unsigned int powerSwitchingMode;
    unsigned int overCurrentProtection;
    unsigned int overCurrentMode;
    unsigned int powerOnDelay;

    /* USB Device List */
    List *usbDeviceList;

    /* USB ED Queue List */
    List *controlEDList;
    List *bulkEDList;
    List *interrupt32EDList;
    List *interrupt16EDList;
    List *interrupt08EDList;
    List *interrupt04EDList;
    List *interrupt02EDList;
    List *interrupt01EDList;
    List *isochronousEDList;

    /*
     *   IOThread synchronization -
     *      commandLock prevents more than one thread from
     *      accessing the usbCommandList at the same time.
     *
     */
    NXConditionLock *commandLock;
    NXLock *processedLock;
    NXLock *errorLock;
    NXLock *timeLock;

    NXConditionLock *installLock;
    NXConditionLock *plumberLock;
    NXConditionLock *timeoutLock;

    List *usbCommandList;
    List *usbProcessedList;
    List *errorTransferList;
    List *timeoutList;

    msg_header_t machMessage;
    port_t msgPort;

    /*  Miscellaneous */
    BOOL ignoreRHSC;
}


/* Highest level device driver methods */

+ (BOOL)probe:deviceDescription;

- probeForUSB_OHCI:(id)deviceDescription;
- initFromDeviceDescription: deviceDescription;
- (unsigned int)initMemBaseFromDeviceDescription:(id)deviceDescription;
- (unsigned int)initIRQFromDeviceDescription:(id)deviceDescription;
- initOHCIRegistersFromDeviceDescription:(id)deviceDescription;

- startHardware;
- enumerateDevices;
- (int)installDeviceOnPort:(int)portnum;

- (void)appendEndpoint:(USBEndpoint *)newEndpoint to:(List *)edList;
- (void)removeEndpoint:(USBEndpoint *)thisEndpoint;
- (void)insertInterruptEndpoint:(USBEndpoint *)newED atInterval:(int)intInterval;

- (int)purgeDoneQueue;
- (void)processErrorTransfers;
- (void)processTimeouts;
- (void)pauseEndpoint:(USBEndpoint *)endPoint;
- (char *)getStringDescriptor:(int)sindex fromUsb:(int)usbAddress atEndpoint:(int)endpoint;

- (NXConditionLock *)installLock;
- (NXConditionLock *)plumberLock;
- (NXConditionLock *)timeoutLock;


- (void)idleDeviceOnPort:(int)portnum;
- (void)activateDevice:(USBDevice *)device;
- (void)ignoreRHSC:(BOOL)flag;



/* External Interface Protocol */
- (BOOL)isUSBHost;

- (BOOL)hardwareIsUp:(int)usbAddress;

- (int)connect:(id)sender toDeviceClass:(int)usbClass subClass:(int)usbSubClass;

- (int)doRequestOnAddress:(int)usbAddress 
                 endpoint:(int)endpointNum
                  request:(standardRequest_t *)devReq 
                     data:(unsigned char *)reqData
		  timeOut:(int)hardTimeOut
                     from:(id)sender;

- (int)doIOonAddress:(int)usbAddress 
            endpoint:(int)endpointNum  
           direction:(int)dataDir 
                data:(unsigned char *)reqData 
               ndata:(int)numdata 
	     timeOut:(int)hardTimeOut
                from:(id)sender;




/* MACH MESSAGING METHODS */

- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)localInterrupt;
- (void)timeoutOccurred;
- (void)commandRequestOccurred;
- (void)receiveMsg;
- (void)otherOccurred:(int)msgID;


/* Mid-level hardware management */
- (void)initPortPower;
- (void)initRootHubConfiguration;
- (BOOL)deviceOnPort:(int)portnum;
- (void)resetPort:(int)numport;
- (int)deviceSpeed:(int)portnum;

- (unsigned int)readPortStatus:(int)portnum;
- (void)writePortStatus:(int)iport value:(unsigned int)value;
- (List *)timeoutList;
- (NXLock *)timeLock;


@end


