Preface:

I am in no way affiliated with AVMATRIX.

I bought this card on Amazon for around $350 because it has the same capabilities as the Magewell Pro Capture Quad HDMI Video Capture Card, and I wanted to see if it held up in comparison. The Magewell card is a $900 card, as opposed to this one. 

Once I got the card, I found the standard ./install -did not work- on Fedora, and the code was slightly outdated for kernel 6.1. On top of that the drivers were being hosted on OneDrive.. which is sketchy. 

To add to that, since I also own the Magewell card already, I was able to do a driver comparison, and I found that this company had done a copy/paste of the Magewell driver install bash scripts and just modified them with their own driver sources.  This made porting over the DKMS functionality (and required kernel module signing) much easier!

Therefore I updated their drivers for them, pointed out all the things wrong, and sent them an e-mail about it. In the meantime, here is the full driver source, which is has been updated and working on Fedora 37 as of Kernel 6.2. 

The license for this project is GPL, as both the AVMATRIX driver -AND- the Magewell driver use GPL:

AVMATRIX:
```
$ grep -rni . -e license
./src/hws_video.c:5794:MODULE_LICENSE("GPL");
```

Magewell:
```
$ grep -rni . -e license
./src/sources/avstream/capture.c:611:MODULE_LICENSE("GPL");
```

Basic install instructions:
```
git clone https://github.com/GloriousEggroll/AVMATRIX-VC41-VC42-CAPTURE
cd AVMATRIX-VC41-VC42-CAPTURE
./dkms-install.sh
reboot
```

Note: Make sure there are no spaces in the directory path or the scripts may fail:

Good path:
```
	/home/someuser/Downloads/AVMATRIX-VC41-VC42-CAPTURE
```
Bad path:
```
    /home/someuser/Downloads/AVMATRIX VC41 VC42 CAPTURE/
```

After a successful installation, you should see something similar to:
```
========================================================

Install Successfully!"
For more information please check the docs directory or"
contact sales@avmatrix.com"

========================================================
```
NOTE: You must reboot the system for the new driver module to take effect.

To use:

Install obs-studio.

Sources > Video Capture Device (V4L2) > HVideo1 (HWS)

Uninstall:
```
$ ./scripts/hws-uninstall.sh
```
