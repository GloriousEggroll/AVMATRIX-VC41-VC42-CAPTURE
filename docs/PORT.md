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
