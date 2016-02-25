

/* Standard Descriptor Types (pg 215 USB Book */
#define  DEVICE_DESC    1
#define  CONFIG_DESC    2
#define  STRING_DESC    3
#define  INTERFACE_DESC 4
#define  ENDPOINT_DESC  5


/* Standard Request Valid bmRequest types */
#define UT_WRITE          0x00
#define UT_READ           0x80
#define UT_STANDARD       0x00
#define UT_CLASS          0x20
#define UT_VENDOR         0x40
#define UT_DEVICE         0x00
#define UT_INTERFACE      0x01
#define UT_ENDPOINT       0x02
#define UT_OTHER          0x03

#define UT_READ_DEVICE            (UT_READ  | UT_STANDARD | UT_DEVICE)
#define UT_READ_INTERFACE         (UT_READ  | UT_STANDARD | UT_INTERFACE)
#define UT_READ_ENDPOINT          (UT_READ  | UT_STANDARD | UT_ENDPOINT)
#define UT_WRITE_DEVICE           (UT_WRITE | UT_STANDARD | UT_DEVICE)
#define UT_WRITE_INTERFACE        (UT_WRITE | UT_STANDARD | UT_INTERFACE)
#define UT_WRITE_ENDPOINT         (UT_WRITE | UT_STANDARD | UT_ENDPOINT)
#define UT_READ_CLASS_DEVICE      (UT_READ  | UT_CLASS | UT_DEVICE)
#define UT_READ_CLASS_INTERFACE   (UT_READ  | UT_CLASS | UT_INTERFACE)
#define UT_READ_CLASS_OTHER       (UT_READ  | UT_CLASS | UT_OTHER)
#define UT_READ_CLASS_ENDPOINT    (UT_READ  | UT_CLASS | UT_ENDPOINT)
#define UT_WRITE_CLASS_DEVICE     (UT_WRITE | UT_CLASS | UT_DEVICE)
#define UT_WRITE_CLASS_INTERFACE  (UT_WRITE | UT_CLASS | UT_INTERFACE)
#define UT_WRITE_CLASS_OTHER      (UT_WRITE | UT_CLASS | UT_OTHER)
#define UT_WRITE_CLASS_ENDPOINT   (UT_WRITE | UT_CLASS | UT_ENDPOINT)
#define UT_READ_VENDOR_DEVICE     (UT_READ  | UT_VENDOR | UT_DEVICE)
#define UT_READ_VENDOR_INTERFACE  (UT_READ  | UT_VENDOR | UT_INTERFACE)
#define UT_READ_VENDOR_OTHER      (UT_READ  | UT_VENDOR | UT_OTHER)
#define UT_READ_VENDOR_ENDPOINT   (UT_READ  | UT_VENDOR | UT_ENDPOINT)
#define UT_WRITE_VENDOR_DEVICE    (UT_WRITE | UT_VENDOR | UT_DEVICE)
#define UT_WRITE_VENDOR_INTERFACE (UT_WRITE | UT_VENDOR | UT_INTERFACE)
#define UT_WRITE_VENDOR_OTHER     (UT_WRITE | UT_VENDOR | UT_OTHER)
#define UT_WRITE_VENDOR_ENDPOINT  (UT_WRITE | UT_VENDOR | UT_ENDPOINT)



/* Valid bRequest types commands (pg 236 USB Book) */

#define UR_GET_STATUS             0x00
#define UR_CLEAR_FEATURE          0x01
#define UR_SET_FEATURE            0x03
#define UR_SET_ADDRESS            0x05
#define UR_GET_DESCRIPTOR         0x06
#define UR_SET_DESCRIPTOR         0x07
#define UR_GET_CONFIG             0x08
#define UR_SET_CONFIG             0x09
#define UR_GET_INTERFACE          0x0a
#define UR_SET_INTERFACE          0x0b
#define UR_SYNCH_FRAME            0x0c
#define UR_GET_BUS_STATE          0x02
#define UR_GET_HID_DESCRIPTOR     0x06
#define UR_SET_HID_DESCRIPTOR     0x07

#define UR_GET_REPORT             0x01
#define UR_SET_REPORT             0x09
#define UR_GET_IDLE               0x02
#define UR_SET_IDLE               0x0a
#define UR_GET_PROTOCOL           0x03
#define UR_SET_PROTOCOL           0x0b

#define UF_ENDPOINT_HALT  0
#define UF_DEVICE_REMOTE_WAKEUP   1


/* USB ED/TD Direction 2-bit Field    */
#define DIR_SETUP  0x00      /* To Endpoint       */
#define DIR_OUT    0x01      /* To Endpoint       */
#define DIR_IN     0x02      /* From Endpoint     */
#define DIR_TD     0x00      /* Dir taken from TD */


#define NO_INTERRUPT         0x07
#define TYPE_GET_DESCRIPTOR  0x06

#define TOGGLE_AUTO 0x0
#define TOGGLE_0    0x2
#define TOGGLE_1    0x3


/*******   USB DATA STRUCTURES   ********/


/* 8-byte USB Standard Request */

#define STANDARD_REQ_LENGTH 8
typedef struct {
    unsigned char  bmRequestType;
    unsigned char  bRequest;

    union {
	unsigned short word;
	struct {
	    unsigned char low;
	    unsigned char high;
	} field;
    } wValue;

    unsigned short wIndex;
    unsigned short wLength;
} standardRequest_t;


/*
 *  Standard USB Device descriptor data structure
 *  returned from a GET_DESCRIPTOR 
 *
 */

#define DV_DESC_LENGTH 18
typedef struct {
    unsigned char  length;
    unsigned char  descriptorType;
    unsigned short bcdReleaseNum;
    unsigned char  class;
    unsigned char  subClass;
    unsigned char  protocol;
    unsigned char  maxPacketSize;
    unsigned short vendorID;
    unsigned short productID;
    unsigned short deviceReleaseNum;
    unsigned char  manufacIndex;
    unsigned char  productIndex;
    unsigned char  serialIndex;
    unsigned char  numConfigs;
} deviceDescriptor_t;

#define CF_DESC_LENGTH 9
typedef struct {
    unsigned char  length;
    unsigned char  descriptorType;
    unsigned short totalLength;
    unsigned char  numInterfaces;
    unsigned char  configValue;
    unsigned char  configIndex;
    unsigned char  attributes;
    unsigned char  maxPower;  /* Misnomer, actually this is max current */
} configDescriptor_t;


#define IF_DESC_LENGTH 9
typedef struct {
    unsigned char  length;
    unsigned char  descriptorType;
    unsigned char  interfaceNum;
    unsigned char  altSetting;
    unsigned char  numEndpoints;
    unsigned char  class;
    unsigned char  subClass;
    unsigned char  protocol;
    unsigned char  interfaceIndex;
} interfaceDescriptor_t;


#define EP_DESC_LENGTH 7
typedef struct {
    unsigned char  length;
    unsigned char  descriptorType;
    unsigned char  address;
    unsigned char  attributes;
    unsigned short maxPacketSize;
    unsigned char  interval;
} endpointDescriptor_t;


