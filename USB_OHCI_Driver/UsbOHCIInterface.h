/*
 * Copyright (c) 2000 Howard R. Cole
 * All rights reserved.
 *
 */

#import <objc/Object.h>
#import "usb.h"

@protocol OHCI_Interface

- (BOOL)isUSBHost;
- (BOOL)hardwareIsUp:(int)usbAddress;

- (int)connect:(id)sender toDeviceClass:(int)usbClass subClass:(int)usbSubClass;

- (int)doRequestOnAddress:(int)usbAddress 
                 endpoint:(int)endpointNum
                  request:(standardRequest_t *)devReq 
                     data:(unsigned char *)reqData
                  timeOut:(int)hardTimeOut
                     from:(id)sender;

- (int)doIOonAddress:(int)usbAddress endpoint:(int)endpointNum  
                                    direction:(int)dataDir 
                                         data:(unsigned char *)reqData 
                                        ndata:(int)numdata 
                                      timeOut:(int)hardTimeOut
                                         from:(id)sender;

@end


