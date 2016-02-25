/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#define KERNEL 1

#import <driverkit/interruptMsg.h>
#import <kernserv/prototypes.h>
#import <machkit/NXLock.h>
#import "USBDevice.h"
#import "USBEndpoint.h"
#import "USBTransfer.h"

#define TRANSFER_SETUP      0
#define TRANSFER_INPROGRESS 1
#define TRANSFER_DONE       2


/*  This object does not manage the allocation or
 *  release of any of the objects in its containers.
 *  It simply keeps lists of them.
 */
@interface TransferRequest : Object
{
    /* Device and data */
    USBDevice         *device;
    USBEndpoint       *endpoint;
    standardRequest_t *devReq;
    unsigned char     *reqData;
    unsigned int      dataLength;
    unsigned int      dataDir;
    List              *tdList;

    /* Command */
    int              devCmd;
    int              completionCode;
    port_t           timeOutPort;
    ns_time_t        expireTime;

    /* IPC */
    NXConditionLock  *transferLock;
}

- init;
- (void)addTransfer:(USBTransfer *)newTD;
- (void)removeTransfer:(USBTransfer *)oldTD;
- (void)removeTransferAt:(int)tdIndex;

- (USBTransfer *)transferAt:(int)tdIndex;
- (int)numTDsQueued;
- (USBTransfer *)isTDQueued:(unsigned int)tdAddress;

- (void)device:(USBDevice *)newDevice;
- (USBDevice *)device;

- (void)endpoint:(USBEndpoint *)newEndpoint;
- (USBEndpoint *)endpoint;

- (void)deviceRequest:(standardRequest_t *)newReq;
- (standardRequest_t *)deviceRequest;

- (void)data:(unsigned char *)data;
- (unsigned char *)data;

- (void)dataLength:(unsigned int)len;
- (unsigned int)dataLength;

- (void)dataDir:(unsigned int)dir;
- (unsigned int)dataDir;

- (void)command:(int)cmd;
- (int)command;

- (void)completionCode:(int)code;
- (int)completionCode;

- (void)timeOutPort:(port_t)intPort;
- (port_t)timeOutPort;

- (void)expireIn:(int)delay;
- (ns_time_t)expireTime;

- (NXConditionLock *)transferLock;

@end
