/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 */

#import "TransferRequest.h"

@implementation TransferRequest

- init
{
    [super init];
    
    tdList = [[List alloc] init];
    transferLock = [[NXConditionLock alloc] initWith:TRANSFER_SETUP];
    expireTime = 0;
    
    return self;
}

- free
{
    [tdList free];
    [transferLock free];
    return [super free];
}

- (void)addTransfer:(USBTransfer *)newTD
{
    [tdList addObject:newTD];
    return;
}

- (void)removeTransfer:(USBTransfer *)oldTD
{
    [tdList removeObject:oldTD];
}

- (void)removeTransferAt:(int)tdIndex
{
    [tdList removeObjectAt:tdIndex];
}

- (USBTransfer *)transferAt:(int)tdIndex
{
    return [tdList objectAt:tdIndex];
}


- (int)numTDsQueued
{
    return [tdList count];
}
     


- (USBTransfer *)isTDQueued:(unsigned int)tdAddress
{
    int itd,ntds = [tdList count];

    for(itd=0; itd<ntds; itd++) {
	if([[tdList objectAt:itd] physicalAddress] == tdAddress)
	    return [tdList objectAt:itd];
    }

    return nil;
}



- (void)device:(USBDevice *)newDevice
{
    device = newDevice;
}

- (USBDevice *)device
{
    return device;
}


- (void)endpoint:(USBEndpoint *)newEndpoint
{
    endpoint = newEndpoint;
}

- (USBEndpoint *)endpoint
{
    return endpoint;
}


- (void)deviceRequest:(standardRequest_t *)newReq
{
    devReq = newReq;
}

- (standardRequest_t *)deviceRequest
{
    return devReq;
}


- (void)data:(unsigned char *)data
{
    reqData = data;
}

- (unsigned char *)data
{
    return reqData;
}


- (void)dataLength:(unsigned int)len
{
    dataLength = len;
}

- (unsigned int)dataLength
{
    return dataLength;
}


- (void)dataDir:(unsigned int)dir
{
    dataDir = dir;
}

- (unsigned int)dataDir
{
    return dataDir;
}


- (void)command:(int)cmd
{
    devCmd = cmd;
}

- (int)command
{
    return devCmd;
}


- (void)completionCode:(int)code
{
    completionCode = code;
}

- (int)completionCode
{
    return completionCode;
}


- (NXConditionLock *)transferLock
{
    return transferLock;
}

- (void)timeOutPort:(port_t)intPort
{
    timeOutPort = intPort;
}

- (port_t)timeOutPort
{
    return timeOutPort;
}



- (void)expireIn:(int)delay
{
    ns_time_t tdelay = delay;

    if(delay > 0) {
      IOGetTimestamp(&expireTime);

      /* Remember, timestamp is in -nanoseconds- */
      expireTime += tdelay*1000000000;
    }
    else 
      expireTime = 0;

    return;
}


- (ns_time_t)expireTime
{
    return expireTime;
}


@end
