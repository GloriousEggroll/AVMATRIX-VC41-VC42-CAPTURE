# AVMatrix VC41/VC42 capture card driver for Linux

This driver runs AVMatrix's multi-channel PCIe capture cards (the VC41, VC42 and related models), each with one, two or four inputs at up to 1920×1080 at 60 Hz, with their stereo audio. For each input it gives you:

- a video device named **HVideo *n*** (for example `/dev/video0`), which OBS, `v4l2-ctl` and other V4L2 programs can open;
- a sound card named **HAudio *n***, which ALSA, PipeWire and PulseAudio programs can record from.

*n* counts the inputs from 1.

The driver is not part of the Linux kernel. `install.sh` builds it with DKMS, which rebuilds it each time you install a new kernel.

## Status of this version

Version 1.1.0 brings over the fixes made to the sister driver for the AVMatrix VC12-4K ([AVMATRIX-VC12-4K-CAPTURE](https://github.com/GloriousEggroll/AVMATRIX-VC12-4K-CAPTURE)): frame delivery, input information, a new capture path, crash fixes and the installer. **None of these changes has been tested on a VC41, a VC42 or any other card this driver supports.** They were built against nine distributions' kernels and checked against the VC12-4K changes and against the kernel's own driver for these cards, but they have never run on one.

If you have one of these cards, please try it and [open an issue](../../issues) with what you find, working or not. Include the card model, `lspci -nn -d 8888:` and `lspci -nn -d 1f33:` output, and the kernel log (`sudo dmesg | grep -i hws`). [docs/PORT.md](docs/PORT.md) lists what each change does and what to check.

## Supported hardware and systems

- **Cards:** PCI IDs 8888:9534, 8524, 8504, 6504, 8532, 8512, 8501 and 1F33:8534, 8554, 6524, 6502, 8504, 8524. Which of these are the VC41 and the VC42 isn't documented.
- **Architecture:** x86-64.
- **Builds against:** Fedora 44 and Arch (7.2.11), Ubuntu 24.04 (6.8), Debian 12 (6.1), Ubuntu 22.04 (5.15), CentOS Stream and AlmaLinux 9 (5.14) and 10 (6.12). The CI workflow in `.github/workflows/build.yml` checks these on every push.

### The kernel's own driver

Linux 7.2 and later include `hws`, a driver for the same cards. Whichever of the two loads first gets the card. `install.sh` writes `/etc/modprobe.d/hws-capture.conf`, which stops `hws` from loading, so this driver gets the card. To use the kernel's driver instead, run `./uninstall.sh` (or delete that file) and reboot.

## Install

### 1. Install the build tools and kernel headers

The headers must match the kernel you are running (`uname -r`).

| Distribution | Command |
|---|---|
| Fedora | `sudo dnf install dkms gcc make kernel-devel-$(uname -r)` |
| Ubuntu, Debian | `sudo apt update && sudo apt install dkms gcc make linux-headers-$(uname -r)` |
| Arch | `sudo pacman -Syu dkms gcc make linux-headers`, then reboot if the kernel was updated |

Desktop installs have the kernel's video and sound modules. Minimal kernels (cloud and some server installs) leave them out, and the driver then fails to load. Add them like this:

| Distribution | Command |
|---|---|
| Fedora | `sudo dnf install kernel-modules-$(uname -r)` |
| Ubuntu | `sudo apt install linux-modules-extra-$(uname -r)` |

### 2. Run the installer

```sh
git clone https://github.com/GloriousEggroll/AVMATRIX-VC41-VC42-CAPTURE.git
cd AVMATRIX-VC41-VC42-CAPTURE
./install.sh
```

`install.sh` asks for your password through `sudo`. It copies the sources to `/usr/src/HwsCaptureForLinux-<version>`, builds the module for every installed kernel that has headers, and loads it. It ends with one of these lines:

- `Loaded.` The driver is running.
- `The driver is already loaded. Reboot to use the version just installed (<version>).`
- `The in-kernel hws driver has the card. Reboot: ...` See [The kernel's own driver](#the-kernels-own-driver).
- `This kernel lacks modules the driver needs`, followed by the package to install (see step 1).
- A Secure Boot message (see the next step).

The path may contain spaces. The installer writes nothing into the folder you run it from.

### 3. Secure Boot: enrol the signing key once

With Secure Boot on, the kernel loads only modules signed with a key it trusts. DKMS signs the module with its own key, and you enrol that key once. `install.sh` checks this and prints the steps. They are:

1. Import the key and choose a one-time password:
   - Fedora and Arch: `sudo mokutil --import /var/lib/dkms/mok.pub`
   - Ubuntu: `sudo mokutil --import /var/lib/shim-signed/mok/MOK.der`

   On Ubuntu, DKMS may ask for this password itself during the install. Then the key is already queued and `install.sh` says so. Skip to step 2.
2. Reboot. A blue screen says **Press any key to perform MOK management**. Press a key within 10 seconds. If the countdown runs out, the request is dropped. Run the import again and reboot.
3. Choose **Enroll MOK**, then **Continue**, then **Yes**, type the password, and choose **Reboot**.

To check: `mokutil --test-key /var/lib/dkms/mok.pub` (or the Ubuntu path) prints `is already enrolled`. Later installs and kernel updates reuse the same key.

### 4. Check that it works

With the card fitted, the driver loads at boot. The checks below use `v4l2-ctl` and `arecord`. Install them if you don't have them:

| Distribution | Command |
|---|---|
| Fedora | `sudo dnf install v4l-utils alsa-utils` |
| Ubuntu, Debian | `sudo apt install v4l-utils alsa-utils` |
| Arch | `sudo pacman -S v4l-utils alsa-utils` |

Then run:

```sh
v4l2-ctl --list-devices        # shows "HVideo 1" and its /dev/video node, one per input
arecord -l                     # shows a card "HAudio 1", one per input
sudo dmesg | grep -i hws
modinfo -F version HwsCapture
```

## Use it in OBS

1. Add a **Video Capture Device (V4L2)** source and choose **HVideo *n*** for the input you want.
2. Set **Resolution** to the input's size (for example 1920x1080) and **Video Format** to **YUYV 4:2:2**. Another size works too. The driver then scales on the CPU.
3. Set **Color Range** to **Full**. The card delivers full-range video. With **Partial**, blacks look grey.
4. For sound, add an **Audio Input Capture** source and choose **HAudio *n***. To hear it, set the source's monitoring in **Advanced Audio Properties**.

Several programs can capture from one input at the same time. They share one frame size: while one program is capturing, the others get its size. Each can choose its own frame rate.

## Upgrade

```sh
cd AVMATRIX-VC41-VC42-CAPTURE
git pull
./uninstall.sh
./install.sh
```

Reboot if the installer says the driver is already loaded.

## Uninstall

```sh
./uninstall.sh
```

`uninstall.sh` removes every version this installer or the old `scripts/hws-*.sh` installers put on the system: the DKMS entries, `/usr/src/HwsCapture*`, `/usr/local/share/HWS`, the `/usr/bin/hws-*.sh` links, any `HwsCapture.ko*` under `/lib/modules`, and `/etc/modprobe.d/hws-capture.conf`. It keeps `/etc/modprobe.d/hws.conf` if you made one. If the driver is loaded, it stays loaded until you reboot.

The old installers of this driver and of the VC12-4K driver used the same `/usr/local/share/HWS` and `/usr/bin/hws-*.sh` paths, so uninstalling either removes what both old installers left there.

## Options

Set options in `/etc/modprobe.d/hws.conf`, for example:

```
options HwsCapture debug_dma=1
```

They take effect the next time the driver loads, so reboot after a change.

| Option | Default | What it does |
|---|---|---|
| `debug_dma` | off | Records the card's DMA address registers at each capture start and stop, for driver development. Leave it off. |

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| No HVideo device | Run `lspci -nn -d 8888:` and `lspci -nn -d 1f33:`. If the card isn't listed, reseat it. If it is, run `sudo dmesg \| grep -i hws` and see the next rows. |
| The card is listed, but `/sys/bus/pci/drivers/hws/` has it | The kernel's own driver has it. Reboot after `install.sh`; see [The kernel's own driver](#the-kernels-own-driver). |
| `modprobe: ERROR: ... Key was rejected by service` | Secure Boot is on and the DKMS key isn't enrolled. Follow [step 3](#3-secure-boot-enrol-the-signing-key-once). |
| `Unknown symbol in module` | The kernel's video and sound modules are missing. Install the package from [step 1](#1-install-the-build-tools-and-kernel-headers). |
| `build failed` during install | The headers don't match the running kernel. Install the headers for `uname -r`, or reboot into the newest kernel. The full log is in `/var/lib/dkms/HwsCaptureForLinux/<version>/build/make.log`. |
| A blue picture | The input sees no signal, or an input larger than 1920×1080 (the kernel log then says `unsupported input`). Check the cable and the source's output mode. |
| A black picture, and `HDCP active, delivering black frames` in the kernel log | The source protects its output with HDCP. The driver never passes protected video. Turn HDCP off on the source. |
| Colours look washed out in OBS | Set the source's **Color Range** to **Full**. |

## Limitations

- **Video format:** YUYV 4:2:2 only. Cards that capture YV12 or another format internally are converted to YUYV on the CPU.
- **Input:** up to 1920×1080 at 60 Hz per input. Interlaced input arrives deinterlaced as progressive frames.
- **Output sizes:** the input's size, or one of 12 standard sizes from 720×480 to 1920×1080, scaled on the CPU.
- **Audio:** 48 kHz, stereo, 16-bit per input. The line-in input some models have isn't supported.
- **HDCP:** protected video is delivered as black frames.

## What's in this repository

- `install.sh`, `uninstall.sh`: install and remove the driver. `dkms-install.sh` runs `install.sh`.
- `CHANGELOG.md`: what changed in each release. `SECURITY.md`: how to report a security problem.
- `src/`: the driver source.
- `tests/`, `tools/`: test scripts and developer tools. `docs/` holds the plan for the 1.1.0 changes (`SPEC.md`) and what each change came from and how to test it (`PORT.md`).
- `doc/`, `quick_start.txt`, `RelaseNote.txt` and `play/` are AVMatrix's original material. Their install steps are out of date; follow this README instead.

## Background and licence

The original README of this repository, by GloriousEggroll, who ported the vendor driver to newer kernels and added DKMS support:

> Preface:
>
> I am in no way affiliated with AVMATRIX.
>
> I bought this card on Amazon for around $350 because it has the same capabilities as the Magewell Pro Capture Quad HDMI Video Capture Card, and I wanted to see if it held up in comparison. The Magewell card is a $900 card, as opposed to this one.
>
> Once I got the card, I found the standard ./install -did not work- on Fedora, and the code was slightly outdated for kernel 6.1. On top of that the drivers were being hosted on OneDrive.. which is sketchy.
>
> To add to that, since I also own the Magewell card already, I was able to do a driver comparison, and I found that this company had done a copy/paste of the Magewell driver install bash scripts and just modified them with their own driver sources.  This made porting over the DKMS functionality (and required kernel module signing) much easier!
>
> Therefore I updated their drivers for them, pointed out all the things wrong, and sent them an e-mail about it. In the meantime, here is the full driver source, which is has been updated and working on Fedora 37 as of Kernel 6.2.

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
