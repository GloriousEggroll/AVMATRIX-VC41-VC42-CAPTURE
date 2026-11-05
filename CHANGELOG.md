# Changelog

User-visible changes. [docs/PORT.md](docs/PORT.md) maps each change to the VC12-4K change it comes from, with what to test.

## 1.1.0

Changes since GloriousEggroll's `main` at `7683b9c`, ported from the VC12-4K driver's 1.1.0. **Not tested on any card this driver supports**; see the README's "Status of this version".

### Install and uninstall

- `install.sh` installs through DKMS only and builds for every installed kernel that has headers. It names the packages to install when something is missing, and with Secure Boot on it prints the key enrolment steps.
- `install.sh` keeps the kernel's own `hws` driver (Linux 7.2 and later) off these cards; `uninstall.sh` undoes that.
- `uninstall.sh` removes every version, including what the old `scripts/hws-*.sh` installers left behind.
- `scripts/` is gone. `dkms-install.sh` runs `install.sh`. The path may contain spaces.
- `modinfo HwsCapture` shows the installed version.
- The module builds on kernels 5.14 to 7.2, including RHEL 9 and 10 and their rebuilds.

### Video

- A blocking read no longer freezes every other program using the card (a deadlock in the ioctl lock).
- Each program gets each frame once: no repeated or mixed frames. Timestamps come from the frame-end interrupt, and a dropped frame shows as a gap in the sequence numbers.
- Frames are copied once, straight into the programs' buffers, from an interrupt thread. The 16 MiB frame queue per input is gone; frames that need converting or scaling use one 4 MiB staging frame per input.
- Several programs can capture one input at once, each at its own frame rate (`S_PARM` divides the input rate).
- The input's own size is listed first and is the default. Other sizes are scaled on the CPU, as before.
- DV timings (`QUERY_DV_TIMINGS` and the rest), input status, and source-change events, so OBS and other programs see the real input mode. The measured frame rate tells 59.94 from 60 Hz.
- Brightness, contrast, saturation and hue now reach the card; they used to be reset to the defaults every second.
- The format reports full-range BT.601 colour, which is what these cards deliver.
- With HDCP on the source, the driver delivers black frames and logs it, as AVMatrix's Windows driver does.
- An input larger than 1920×1080 shows as no signal, with a warning, instead of corrupting frames.
- Capture works after suspend and resume.
- Changing an input's resolution while capturing restarts that input's capture cleanly.
- The driver recovers a card that lost its run state.
- Unplugging (unbinding) or unloading the driver while programs have it open no longer crashes the kernel. The programs get an error and exit.

### Audio

- The sound cards report themselves as BATCH devices with periods that match the card's packets. On the VC12-4K, PipeWire mistook the 21 ms packets for clock drift without this, which made a low-latency loopback sound robotic.
- While the source sends no audio, the driver delivers silence instead of PipeWire replaying its last buffer as a buzz.
- The first two packets after a recording starts are dropped; on the VC12-4K they held the previous recording's sound.
- Closing or suspending during a recording no longer risks a crash.

### Diagnostics

- `/sys/kernel/debug/hws-<pci address>/status` shows each input's signal, frame rate, frame counts, audio gaps and consumers.
- New option `debug_dma` (off by default) for driver development.
