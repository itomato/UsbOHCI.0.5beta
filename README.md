# Introduction

This is a device driver for an OHCI (Open Host Controller Interface) USB host controller board.  For many people, this will be disappointing news because the USB host controllers built into all motherboards using the Intel chipset are of the UHCI (Universal Host Controller Interface) variety.  As fate would have it, my development machine is just old enough that is does not have USB built into the motherboard, so when I decided to write a driver, I had to install a USB PCI card.  I discovered that nearly all PCI cards use OHCI chipsets.  So, an OHCI it is for the time being.  The board I used is a Belkin two-port card since it is inexpensive and readily available.  Any OHCI compliant board should work.

# Installation

Installing this driver is the same as any other driver.  Drag it into the /usr/Devices directory and use Configure.app to select the memory base address and IRQ line.  When you re-boot your machine, messages indicating that the controller board has been detected and installed will be displayed and placed in the /usr/adm/messages.  These messages should look similar to this:

	Sep 26 12:15:06 peyote mach: USB Open Host Controller Driver (OHCI) by Howard R. Cole
	Sep 26 12:15:06 peyote mach: Registering: UsbOHCI0
	Sep 26 12:15:06 peyote mach: UsbOHCI0: Base=0x80000000, IRQ=11

Of course, the base address and IRQ would have the values which you selected with Configure.app rather than the values shown here.

This driver also recognizes devices which are plugged into the USB after booting up.  When you add such a device, this driver will query it for its configuration, and insert its endpoints into the proper queues.  However, you must start up the proper device driver by hand.  As an example, here's the /usr/adm/messages output when I connect my printer to the USB after boot:

	Sep 26 12:18:44 peyote mach: usb - device connect port 2
	Sep 26 12:18:44 peyote mach: usb - waiting 2 seconds for device to come ready.
	Sep 26 12:18:47 peyote mach: usb - device installed on port 2

Now, if a user tries to use the printer at this point, he gets an error that the device doesn't exist.  He must load the USBPrinter driver as the root user like this

	peyote#  driverLoader d=USBPrinter

When the command above is executed, /usr/adm/messages records the action like this:

	Sep 26 12:19:02 peyote mach: USB Printer Driver v0.5beta by Howard R. Cole
	Sep 26 12:19:02 peyote mach: usblp0: Lexmark Optra E312 at usb address 2
	Sep 26 12:19:02 peyote mach: Registering: usblp0

At this point, the printer is ready for use as the device /dev/usblp0.  I am currently working on a daemon which will find the proper driver and load it for you when a new device is connected.


# Problems

This is a beta level driver and there are known bugs in it.  These bugs do not seem to interfere with normal operation; however, all bugs existing at the kernel level are serious and potentially dangerous to your data.  Use this driver at your own risk.  I am releasing this driver now so other developers can have a chance to examine the source, make improvements, and write device drivers for other USB devices.

Also note: my USB board refuses to work with any interrupt other than IRQ 11.  I don't know why.  I'm not sure if the board I have is hard-wired to that address; this board comes with no technical documentation.  All attempts I made to use a different interrupt line were unsuccessful.  If anyone successfully uses any other interrupt line, please let me know.


# Device Drivers

A driver for the host controller is quite useless without drivers for the individual devices which you can connect.  So this host controller driver will be of limited utility to users at this point.  I have written a basic device driver for USB postscript printers (I use a Lexmark Optra E312).  The source code for this driver is available along with the compiled binary.  It is my hope that others will use the source and the programming notes to write USB device drivers for many, many products.


# Remarks or Questions 

Any remarks or questions you may have regarding this driver may be directed to me at the email address below.  I'm always eager to hear suggestions for new features or better performance.

Howard Cole
Tucson, AZ
hcole@gci-net.com

