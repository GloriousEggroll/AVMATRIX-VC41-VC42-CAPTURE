# VC12-4K fixes ported to this driver

This file maps each change ported from the [VC12-4K driver](https://github.com/GloriousEggroll/AVMATRIX-VC12-4K-CAPTURE) to its commit here, says how it differs, and lists what only someone with a card can check. The plan is in [SPEC.md](SPEC.md).

**None of these changes has run on a VC41, VC42 or any other card this driver supports.** They were built against many kernels and reviewed against the VC12-4K commits and the in-kernel `hws` driver, which supports these cards. If you test them, please report what you see, good or bad, in an issue.

## Baseline

At `7683b9c` (this repository's `main` on 2026-10-20):

| Check | Result |
|---|---|
| Build, Linux 7.2.11 (Nobara 44), `W=1` | builds; 51 warnings. 8 of them come from the positional initialisers in `g_hws_ctrls`, which put `{ 0, 0 }` into the scalar `elem_size`; harmless, and the table goes away when the controls move to the control framework (PR 3). |
| Build matrix (9 distributions) | see below |
| checkpatch (`--no-tree -f`) | `hws_video.c` 2,947 errors, 719 warnings; `hws.h` 68, 56; `hws_reg.h` 19, 71 |

Build matrix at `7683b9c`, `W=1`, with `tools/ci-build.sh` from the VC12-4K repository:

| Distribution | Kernel | Result |
|---|---|---|
| Fedora 44 | 7.2.11 | builds, 51 warnings |
| Arch | 7.2.11 | builds, 50 warnings |
| Ubuntu 24.04 | 6.8 | builds, 50 warnings |
| Ubuntu 22.04 | 5.15 | builds, 48 warnings |
| Debian 12 | 6.1 | builds, 48 warnings |
| CentOS Stream 9 and 10, AlmaLinux 9 and 10 | 5.14, 6.12 | fails: `v4l2_fh_add()` takes two arguments and `vb2_ops.wait_prepare` is gone (RHEL backports) |

The RHEL failures are the ones the VC12-4K driver had; PR 6 ports its fix (`f4732c7`).

## PR 1: audio BATCH

| VC12-4K | Here | Differences |
|---|---|---|
| `f40a4d5` mark the PCM as BATCH and align periods to DMA packets | `18fbd61` | None; the commit applies unchanged. |

Every channel registers one capture PCM, and all of them take `audio_pcm_hardware` and the same open function, so the change covers every channel. The packet size is the same constant (`MAX_DMA_AUDIO_PK_SIZE`, 4096 bytes) on both drivers. The line-in input some IDs have (`m_nCurreMaxLineInChl`) isn't exposed as a PCM by this driver, so it isn't affected.

checkpatch: one more instance each of three existing kinds (`for(;;)`, `||` without spaces, and an indent), from lines that follow the surrounding code. Kept identical to the VC12-4K commit so the two can be compared.

Build: 7.2.11 `W=1`, 51 warnings, as the baseline.

To check on a card: capture the card's audio through PipeWire with a short quantum (for example OBS audio monitoring, or `pw-loopback`). Before this change, the VC12-4K's audio sounded robotic and crackled; after it, clean.

## PR 2: frame delivery

| VC12-4K | Here | Differences |
|---|---|---|
| `7243fdf` frame delivery check and baseline runner | `ed02e3c`, `3a3c195` | The runner uses module `HwsCapture` and 1080p runs (native with 4 and 1 buffers, 720p scaled). |
| `890ff94` status thread sleeps idle | `7c1eb14` | None. |
| `a319e19` kvzalloc frame-queue buffers | `4fd4f15` | One slot set per channel here, not four; the YUV2 and rotation buffers join the single failure path. |
| `2d8e283` size DMA buffers for 4096×2160 | `cec6e9c` | Only the bound and the no-signal handling. The input is limited to 1920×1080, which fits the 4 MiB buffers. An input above that used to keep the previous size's DMA lengths; it now shows as no signal, with one warning per size. |
| `23392ec` per-queue locking | `b478330` | None; the ioctl and queue code is the same. `engine_lock` is per channel. |
| `49080f5` refuse format changes while buffers exist | `f83300c` | `S_FMT` is the same. Every conversion path in this worker writes the output size, so the same check and payload apply. |
| `8f5cb58` stop_streaming waits for in-flight buffers | `afa586b` | Ten completion points in this worker, not three. |
| `68f0c92` frame-end timestamps and frame numbers | `5f38bec` | All four channels' interrupt blocks. Toggle 0 completes the frame here too (`MemCopyVideoToSteam()` copies the second half then). |
| `7cc4188` one frame per consumer, no copies with interrupts off | `ca27b6f` | Written for this driver's single slot buffer. The YV12/NV12, deinterlace, scaling and rotation paths move unchanged into `hws_render_frame()`, which uses the slot's own size and interlace flag. `StartVideoCapture()` used to free every slot without the lock, including one being read; it now frees only READY slots, under the lock. |

Build: the five distributions that build the baseline build this with the same warning counts; CentOS Stream and AlmaLinux 9 and 10 fail with exactly the baseline's errors. checkpatch: no new kinds; `hws_video.c` drops to 2,731 errors and 458 warnings.

What the VC12-4K showed before PR 2 (with OBS, the same worker code): ~240 frames per second delivered from a 60 fps source, 76 of 300 frames unique, and `v4l2-compliance` hanging in its blocking-DQBUF test. `tests/run-baseline.sh` measures all three; run it before and after.

To check on a card, per channel: `tests/run-baseline.sh /dev/videoN` with a 1080p60 source. Expect about 60 fps, no duplicates and no bursts in the framecheck lines, and `v4l2-compliance` finishing. Also capture from two programs at once (two OBS sources on one channel), and from all channels at once, and check each gets every frame once. YV12/NV12 boards and interlaced inputs go through `hws_render_frame()`; a picture that's wrong only there points at it.

## PR 3: input information

| VC12-4K | Here | Differences |
|---|---|---|
| `8def62a` build check against every installed kernel | `cdd8952` | Module `HwsCapture`; the default base is `7683b9c`. |
| `c89526e` unique bus_info, 720×576 mode, no read() | `debe708` | The 720×576 entry was already right here. |
| `00f59a5` measure the input frame rate | `bf928e9` | Every channel's frame-end interrupt feeds its own measurement. |
| `ec373f1` picture controls through the control framework | `f8f3a64` | This driver's status poll rewrites register 91 + 2·ch from `m_brightness[ch]` and the others, which were only ever 0x80, so it reset user settings. `s_ctrl` now updates them too. The old handlers removed are this driver's own. |
| `a9ef468` native size first, followed when idle | `51b15b6` | The VC12-4K's 4K clamps are gone; native sizes are the ones `Get_Video_Status()` accepts (up to 1920×1080, a field counting double). |
| `c466a2f` real frame intervals, per-consumer rates | `00e7e27` | This driver listed 25/50 or 30/60 fps; it now lists the input's rate divided by 1 to 4. |
| `5af2e2b` DV timings, signal status, events, log_status | `884334a` | Timings capability: up to 1920×1080 and 165 MHz, not 4K and 600 MHz. Source-change checks for every channel. |
| `182c304` close a handle's queue before counting it closed | `ae58b90` | None. |
| `9f6cab6` enumerate and accept only deliverable timings | `6b9c627` | None. |
| `483648e` re-initialise the card after suspend | `3785e2c` | Resume also calls `SetHardWareInfo()`, which rewrites register 9 on FPGA versions above 121. |
| `4a87a38` progressive timings only, but accept the input's own | `86623a6` | None; this driver also delivers interlaced input as progressive frames. |
| `8c7644d` store the live DV timings before the baseline runs | `4e0ba85` | None. |
| `f3da7f7` frame rate in frame periods | `2c7c078` | None; covers every channel. |
| `b8cb4e6` signal presence as `V4L2_CID_DV_RX_POWER_PRESENT` | `9216a8a` | A fifth control beside hue; "input signal", since some models are SDI. |

Not ported: `1a794ea`, which drops the hue control because the VC12-4K ignores it. Whether these cards use it is unknown, so it stays.

Build: the five distributions that build the baseline build this; the RHEL family fails with the baseline's errors only. `tests/build-all-kernels.sh` finds no new warnings on 7.2.9 to 7.2.11. With `W=1` there is one: `framegrabber_support_refreshrate` is unused after `00e7e27`, as it was on the VC12-4K, until part 5's cleanup removes it. checkpatch: no new kinds; `hws_video.c` drops to 2,600 errors and 422 warnings.

To check on a card, per channel:
- `v4l2-ctl -d /dev/videoN --query-dv-timings` shows the source's mode and measured rate (59.94 and 60 told apart after about a second of capture); `--list-formats-ext` lists the input's size first.
- `v4l2-ctl --set-ctrl brightness=200` changes the picture and stays changed (it used to reset within a second); `hue` may or may not do anything.
- OBS logs the input in "Log status" and follows a source change without restarting the source.
- A suspend and resume while capturing: capture continues.

## PR 4: capture rework

| VC12-4K | Here | Differences |
|---|---|---|
| `cae50c6` copy each half straight into app buffers from a threaded IRQ | `bbc93c7` | Written for this driver: each channel's frame is two halves in its own DMA buffer (`HLAF_SIZE`, then `DWON_SIZE`), not four quarters in four buffers. One kfifo carries {channel, half, time} for all four channels to one IRQ thread; each channel has its own `cap_lock`. Only native-size progressive YUYV is copied straight; YV12/NV12, interlaced, scaled and rotated frames go through a per-channel staging frame and `hws_render_frame()`. The stale-half mark sits where the vendor's copy path put it. Version-0 cards keep counting halves for their software frame rate. |
| `5bd61fb` probe and remove ordering, error paths, interrupt flags | `082bad0` | All four audio tasklets; the workqueue keeps its name; probe keeps this driver's starting values for the fields the status poll compares with the card's registers. |
| `fa5b301` debugfs status, DMA check, register snapshots | `b0f32aa` | `status` lists every channel. In `dma` and `regsnaps` the four entries are channels, and register 50 + ch is the first half's length. |
| `7df0340` (first part) program the input's DMA lengths before capture starts | `f070a2e` | Only that part: the register 9 value and the canary are VC12-4K specific. |
| `479286e` the card's frame rate when nothing is measured | `2789f0a` | Register 110 is read on the cards this driver's poll already reads it on. |
| `12e91c5` black frames while the source uses HDCP | `1d80599` | Two halves; register 8 is read only on FPGA versions above 121, as this driver's poll did. |
| `46f7ec9` 500 µs pause in the start sequence | `c9defca` | None. The pause comes from the VC12-4K's Windows driver. |
| `96dd3f1` full-range colorimetry | `d7b41b1` | BT.601 encoding at every size, Rec. 709 primaries for HD and SMPTE 170M for SD: the in-kernel `hws` driver's measurement on these cards. The VC12-4K reports a Rec. 709 matrix, measured on that card. |
| `ddc7606` rate-limited LOG_STATUS | `846d5fb` | None. |
| `2ef336a` 50 ms input poll | `168632a` | Without the canary scan. |
| `1f3e39a` silence while the card sends no audio | `10968b9` | Every channel's sound card; debugfs counts per channel. |
| `c433848` `tests/yrange.py` | `8d59bd0` | None. |

Not ported: `8a67155`, `df0a168`, `bf69f64` (the DMA canary, a VC12-4K investigation tool), the register 9 part of `7df0340`, and `0cf7b5d` (`tests/regprobe.py`, written for VC12-4K register probes).

Build: the five distributions that build the baseline build this; the RHEL family fails with the baseline's errors only. No new warnings on 7.2.9 to 7.2.11. checkpatch: no new kinds; `hws_video.c` drops to 2,315 errors and 404 warnings.

This is the part most likely to misbehave on real hardware: it replaces how every frame gets from the card to the apps. To check on a card, per channel:
- `tests/run-baseline.sh /dev/videoN`: about 60 fps, no duplicates, sequence numbers without gaps at a steady source.
- `/sys/kernel/debug/hws-<pci address>/status`: frames counting up, few lost, no "half queue full".
- Capture at a scaled size (720p), from an interlaced source, and on a YV12/NV12 board if you have one: these go through the staging path.
- All channels at once, and stop/start capture repeatedly.
- `tests/yrange.py` on a few frames: Y should span about 0 to 255 if the card delivers full range.
- A source change while capturing: no kernel warnings, capture resumes.

## PR 5: audit fixes

| VC12-4K | Here | Differences |
|---|---|---|
| `af7a1eb` DMA checks behind `debug_dma` | `3a37e7d` | Only the register snapshots; there is no canary. |
| `9a7d8c0` no re-init from the atomic PCM trigger | `eca8f8a` | The re-init holds every channel's `engine_lock` and `cap_lock`, in channel order; no zero-copy to move back. |
| `60ed9a7` no audio into a stopped stream; SUSPEND as STOP | `1f6f3c3` | Covers each channel's sound card. |
| `fed9220` unregister before teardown, free on last close | `e0ae06b` | Every channel's video device and sound card holds a reference. |
| `6e4fd45` stop the status thread on probe failure | `20403c4` | None. |
| `ae6e63e` acknowledge exactly the interrupt bits that are set | `0353598` | Eight known sources (video 0-3, audio 8-11) instead of two. The untested-model warning isn't ported. |
| `693863f` bounded busy wait after stop | `00ea544` | None. |
| `1382cf8` freezable status thread | `8fbb15f` | None. |
| `41c0d63` an all-ones register 8 isn't HDCP | `13ae698` | Combined with the FPGA-version gate. |
| `e02e347` Relaxed Ordering left to the PCI core | `4728f90` | None. |
| `dd669a0` no DMA sync calls on coherent buffers | `bfc9b60` | One buffer per channel. |
| `8377ac9` fail a frame whose half may have been overwritten | `4009bd5` | The half-frame interval is measured per channel, not taken from zero-copy. |
| `78484d4` wake blocked readers on removal | `92004bc` | None. |
| `4a07d5e` recover a card that lost its run state | `e42845f` | Checks every channel. |
| `a4311ca` stop video DMA with a readback | `a75c3e8` | Without the zero-copy stop timeout; remove quiesces every channel. |
| `07860d0` restart the engine on every input-size change | `fd223f0` | Per channel, with the restart counter from `4e12ea3`. |
| `4e12ea3`, `87c6930`, `7b4c70a`, `b9f1c2c`, `1fdf4cb` `switchtest.sh` and `framecheck.py` | `d6e12ec` | One commit; one channel at a time (`CH=n`), the card found through sysfs, no zero-copy reporting. |
| `f3c5ded` drop the stale audio packets after a start | `0acde0c` | Per channel. |
| `e88d445`, `9dda857` `soak.sh` | `126435d`, `ac5f84f`, `154b35c` | Adapted in `154b35c`: one channel, no zero-copy or stray-write columns. |
| `0f2c6c7` remove the unused per-device vb2 queue | `c315596` | None. |
| `aeeb157` remove unused fields, tables, locals | `eebded8` | The scaler it touched doesn't exist here. |
| `d4f6c40` remove `#if 0`, unwrap `#if 1` | `599c620` | This driver's sixteen blocks, by the same kind of script. |
| `0499165` drop unused and repeated includes | `c1804bb` | None. |

Not ported:
- `d6e23f9`, `f772cef`, `8fa4801`: zero-copy.
- `583a751`: a debug knob for testing the zero-copy 6.11 fix.
- `d7cea32`: it changes `tools/dkms-install.sh`, a developer install script from the VC12-4K's part 4 (`a9b2cef`) that isn't ported; part 6's `install.sh` copies only the sources.
- `ff93168`, `ace5f67`: tests for the VC12-4K's GPU-capture issue.

The in-kernel `hws` fix "only init channels the device actually has" has no counterpart here: this driver already sets up and tears down per-channel devices and controls for the same channel count.

Build: no new warnings on 7.2.9 to 7.2.11; `W=1` is down to 24 warnings from 51 at the baseline. checkpatch: no new kinds; `hws_video.c` drops to 2,160 errors and 342 warnings.

To check on a card:
- unbind or unload the driver while OBS captures from it: the programs get an error and exit, the kernel log shows no oops;
- suspend and resume while capturing and while recording audio;
- `tests/switchtest.sh 1920 1080` with `CH=n` per channel while switching the source's resolution;
- `tests/soak.sh` for a long session with OBS;
- the debugfs status file's "other sources" count: should stay 0 (a nonzero value names interrupt bits this driver doesn't know).

## Unknowns

What the VC12-4K showed and these cards may not:
- audio crackling under PipeWire before PR 1;
- stale audio packets after an audio enable;
- whether hue has any effect, on HDMI and on SDI models;
- the colour range delivered;
- whether register 9 at 1080p stops DMA runs past the buffer;
- register 110 (input frame rate) on each FPGA version;
- interlaced input after the capture rework;
- the NV12 path on boards that report `support_yv12`;
- which PCI IDs are the VC41 and which the VC42.
