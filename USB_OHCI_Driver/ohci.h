/*** PCI config registers ***/

#define PCI_BASE_IO_BIT         1
#define PCI_NUM_BASE_ADDRESS    6

#define PCI_COMMAND_REG         0x04
#define PCI_BASEMEM             0x10              /* configuration base memory */
#define PCI_INTERFACE_OHCI      0x10
#define PCI_IRQ_LINE            0x3C
#define PCI_IRQ_ASGN_REG        0x50              /* Byte offset 1 */
#define    IRQ_TYPE_FS          0x80


/*** OHCI registers */

#define HcRevision              0x00	          /* OHCI revision # */
#define  HC_REV_LO(rev)	        ((rev)&0xf)
#define  HC_REV_HI(rev)	        (((rev)>>4)&0xf)
#define  HC_REV_LEGACY(rev)     ((rev) & 0x100)

#define HcControl		0x04
#define  HC_CBSR_MASK           0x00000003 /* Control/Bulk Service Ratio */
#define  HC_RATIO_1_1           0x00000000
#define  HC_RATIO_1_2           0x00000001
#define  HC_RATIO_1_3           0x00000002
#define  HC_RATIO_1_4           0x00000003
#define  HC_PLE	                0x00000004 /* Periodic List Enable */
#define  HC_IE	                0x00000008 /* Isochronous Enable */
#define  HC_CLE	                0x00000010 /* Control List Enable */
#define  HC_BLE	                0x00000020 /* Bulk List Enable */
#define  HC_FS_MASK             0x000000c0 /* HostControllerFunctionalState */
#define  HC_FS_RESET	        0x00000000
#define  HC_FS_RESUME	        0x00000040
#define  HC_FS_OPERATIONAL	0x00000080
#define  HC_FS_SUSPEND          0x000000c0
#define  HC_IR		        0x00000100 /* Interrupt Routing */
#define  HC_RWC                 0x00000200 /* Remote Wakeup Connected */
#define  HC_RWE                 0x00000400 /* Remote Wakeup Enabled */

#define HcCommandStatus	0x08
#define  HC_HCR                 0x00000001 /* Host Controller Reset */
#define  HC_CLF                 0x00000002 /* Control List Filled */
#define  HC_BLF                 0x00000004 /* Bulk List Filled */
#define  HC_OCR                 0x00000008 /* Ownership Change Request */
#define  HC_SOC_MASK            0x00030000 /* Scheduling Overrun Count */

#define HcInterruptStatus       0x0c
#define  HC_SO                  0x00000001 /* Scheduling Overrun */
#define  HC_WDH                 0x00000002 /* Writeback Done Head */
#define  HC_SF                  0x00000004 /* Start of Frame */
#define  HC_RD                  0x00000008 /* Resume Detected */
#define  HC_UE                  0x00000010 /* Unrecoverable Error */
#define  HC_FNO                 0x00000020 /* Frame Number Overflow */
#define  HC_RHSC                0x00000040 /* Root Hub Status Change */
#define  HC_OC                  0x40000000 /* Ownership Change */
#define  HC_MIE                 0x80000000 /* Master Interrupt Enable */

#define HC_ALL_INTRS (HC_SO | HC_WDH | HC_SF | HC_RD | HC_UE | HC_FNO | HC_RHSC | HC_OC)
#define HC_NORMAL_INTRS (HC_SO | HC_WDH | HC_RD | HC_UE | HC_RHSC)



#define HcInterruptEnable       0x10
#define HcInterruptDisable      0x14
#define HcHCCA                  0x18
#define HcPeriodCurrentED       0x1c
#define HcControlHeadED         0x20
#define HcControlCurrentED      0x24
#define HcBulkHeadED            0x28
#define HcBulkCurrentED         0x2c
#define HcDoneHead              0x30
#define HcFmInterval            0x34

#define FRAME_INTERVAL  0x00002EDF

#define HcFrameRemaining        0x38
#define HcFmNumber              0x3c
#define HcPeriodicStart         0x40
#define HcLSThreshold           0x44

#define HcRhDescriptorA	0x48
#define  HC_GET_NDP(s)	((s) & 0xff)    /* Number Downstream Ports */
#define  HC_PSM		0x0100          /* Power Switching Mode    */
#define  HC_NPS		0x0200	        /* No Power Switching      */
#define  HC_DT          0x0400          /* Device Type (compound)  */
#define  HC_OCPM        0x0800          /* OverCurrent Protection Mode */
#define  HC_NOOCP       0x1000          /* No Over Current Protection  */
#define  HC_GET_POTPGT(s)	((s) >> 24)  /* Power On To Power Good Time */

#define HcRhDescriptorB         0x4c

#define HcRhStatus              0x50
#define  HC_LPS                 0x00000001 /* Local Power Status */
#define  HC_OCI	                0x00000002 /* OverCurrent Indicator */
#define  HC_DRWE                0x00008000 /* Device Remote Wakeup Enable */
#define  HC_LPSC                0x00010000 /* Local Power Status Change */
#define  HC_CCIC                0x00020000 /* OverCurrent Indicator Change */
#define  HC_CRWE                0x80000000 /* Clear Remote Wakeup Enable */

#define HcRhPortStatus(n)	(0x50 + (n)*4)    /* 1 based indexing */
#define  HC_CCS                 0x000001     /* Read :  Current Connect Status */
#define  HC_CPE                 0x000001     /* Write:  Clear Port Enable           */
#define  HC_PES                 0x000002     /* Read :  Port Enable Status          */
#define  HC_SPE                 0x000002     /* Write:  Set Port Enable             */
#define  HC_PSS                 0x000004     /* Read :  Port Suspend Status         */
#define  HC_SPS                 0x000004     /* Write:  Set Port Suspend            */
#define  HC_POCI                0x000008     /* Read :  Port Over Current Indicator */
#define  HC_CSS                 0x000008     /* Write:  Clear Suspend Status        */
#define  HC_PRS                 0x000010     /* Read :  Port Reset Status           */
#define  HC_SPR                 0x000010     /* Write:  Set Port Reset              */
#define  HC_PPS                 0x000100     /* Read :  Port Power Status           */
#define  HC_SPP                 0x000100     /* Write:  Set Port Power              */
#define  HC_LSDA                0x000200     /* Read :  Low Speed Device Attached   */
#define  HC_CPP                 0x000200     /* Write:  Clear Port Power            */
#define  HC_CSC                 0x010000     /* Read :  Connect Status change       */
#define  HC_PESC                0x020000     /* R/W  :  Port Enable Status Change   */
#define  HC_PSSC                0x040000     /* R/W  :  Port Suspend Status Change  */
#define  HC_POCIC               0x080000     /* R/W  :  Port OverCurrent Indicator  */
#define  HC_PRSC                0x100000     /* R/W  :  Port Reset Status Change    */


#define HC_LES (HC_PLE | HC_IE | HC_CLE | HC_BLE)


typedef unsigned int hc_physaddr_t;

#define HccaFrameNumber 0x80
#define HccaDoneHead    0x84

#define HC_HCCA_SIZE 256
#define HC_HCCA_ALIGN 256
#define HC_PAGE_SIZE 0x1000
#define HC_PAGE(x) ((x) &~ 0xfff)

#define HC_ED_SIZE 16
#define HC_ED_ALIGN 16

#define HC_CC_NO_ERROR                  0
#define HC_CC_CRC                       1
#define HC_CC_BIT_STUFFING              2
#define HC_CC_DATA_TOGGLE_MISMATCH      3
#define HC_CC_STALL                     4
#define HC_CC_DEVICE_NOT_RESPONDING     5
#define HC_CC_PID_CHECK_FAILURE         6
#define HC_CC_UNEXPECTED_PID            7
#define HC_CC_DATA_OVERRUN              8
#define HC_CC_DATA_UNDERRUN             9
#define HC_CC_BUFFER_OVERRUN            12
#define HC_CC_BUFFER_UNDERRUN           13
#define HC_CC_NOT_ACCESSED              15
#define CC_EXPIRED                      16


/********   OHCI  DATA STRUCTURES   ***********/

/* Endpoint Descriptor definition */
typedef struct {
    union {
	unsigned int word;
	struct {
	    unsigned int funcAddress:7;
	    unsigned int epAddress:4;
	    unsigned int direction:2;
	    unsigned int speed:1;
	    unsigned int skip:1;
	    unsigned int format:1;
	    unsigned int maxPacket:11;
	    unsigned int undef1:5;
	} field;
    } dword0;

    union {
	unsigned int word;
	struct {
	    unsigned int undef1:4;
	    unsigned int tailPointer:28;
	} field;
    } dword1;

    union {
	unsigned int word;
	struct {
	    unsigned int halt:1;
	    unsigned int toggleCarry:1;
	    unsigned int zero:2;
	    unsigned int headPointer:28;
	} field;
    } dword2;

    union {
	unsigned int word;
	struct {
	    unsigned int undef1:4;
	    unsigned int nextED:28;
	} field;
    } dword3;

} ed_t;


    
/* General Transfer Descriptor definition */
typedef struct {
    union {
	unsigned int word;
	struct {
	    unsigned int undef1:18;
	    unsigned int bufferRounding:1;
	    unsigned int directionPID:2;
	    unsigned int delayInterrupt:3;
	    unsigned int dataToggle:2;
	    unsigned int errorCount:2;
	    unsigned int conditionCode:4;
	} field;
    } dword0;

    union {
	unsigned int word;
	struct {
	    unsigned int currentPointer:32;
	} field;
    } dword1;

    union {
	unsigned int word;
	struct {
	    unsigned int undef1:4;
	    unsigned int nextTD:28;
	} field;
    } dword2;

    union {
	unsigned int word;
	struct {
	    unsigned int bufferEnd:32;
	} field;
    } dword3;

} td_t;



/* Isochrounous Transfer Descriptor definition */
typedef struct {
    union {
        unsigned int word;
        struct {
	    unsigned int startingFrame:16;
	    unsigned int undef1:5;
	    unsigned int delayInterrupt:3;
	    unsigned int frameCount:3;
	    unsigned int undef2:1;
	    unsigned int conditionCode:4;
	} field;
    } dword0;

  union {
      unsigned int word;
      struct {
          unsigned int undef1:12;
	  unsigned int bufferPage0:20;
      } field;
  } dword1;

  union {
      unsigned int word;
      struct {
	  unsigned int zero:5;
	  unsigned int nextTD:27;
      } field;
  } dword2;

  union {
      unsigned int word;
      struct {
          unsigned int bufferEnd:32;
      } field;
  } dword3;

  union {
      unsigned int word;
      struct {
          unsigned int psw0:16;
          unsigned int psw1:16;
      } field;
  } dword4;

  union {
      unsigned int word;
      struct {
          unsigned int psw2:16;
          unsigned int psw3:16;
      } field;
  } dword5;

  union {
      unsigned int word;
      struct {
          unsigned int psw4:16;
          unsigned int psw5:16;
      } field;
  } dword6;

  union {
      unsigned int word;
      struct {
          unsigned int psw6:16;
	  unsigned int psw7:16;
      } field;
  } dword7;
} iso_td_t;


  
	
