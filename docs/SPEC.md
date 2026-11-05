# Porting the VC12-4K fixes to the VC41/VC42 driver

This spec plans a best-effort port of the fixes made to the AVMatrix VC12-4K driver ([AVMATRIX-VC12-4K-CAPTURE](https://github.com/GloriousEggroll/AVMATRIX-VC12-4K-CAPTURE), PRs #26–#32) to this driver for the multi-channel cards.

## Request and scope

The repository owner asked, on VC12-4K PR #26 (2026-10-20): "for all of your MRs, could you please also rebase+submit them on [AVMATRIX-VC41-VC42-CAPTURE] as well? they are basically the same driver code, just different cards."

What this port will and won't do:
- **Best effort, untested on hardware.** Nobody working on the port owns a VC41, a VC42 or any other card this driver supports. Each change is ported from the VC12-4K work, checked against the in-kernel `hws` driver where it touches hardware, built against many kernels, and reviewed. It is never run on a card. Every PR says so, lists its unknowns, and leaves testing to the owner and users.
- **Same series shape.** One stacked PR per VC12-4K PR, in the same order, so a reviewer can read the two series side by side.
- **No hardware guesses.** Where the VC12-4K behaviour depended on its hardware (the 4K quarter layout, register 9, FPGA 122 features), the port either keeps this driver's existing behaviour or follows the in-kernel `hws` driver, which supports these cards. It doesn't copy VC12-4K values.
- **Out of scope:** zero-copy (VC12 PR #30), new features with no VC12 counterpart, and the VC12-4K's measurement docs (`docs/results.md` and the register probes), which record that card's hardware.

## How the two drivers differ

Both come from the same vendor code. At the starting points (VC12-4K `bd17e06`, this repository `7683b9c`), 116 of the 136 functions the two `hws_video.c` files share are identical. The differences follow the hardware:

| | VC12-4K (`HwsUHDX1Capture`) | This driver (`HwsCapture`) |
|---|---|---|
| PCI IDs | 8888:8581 | 8888:9534, 8524, 8504, 6504, 8532, 8512, 8501; 1F33:8534, 8554, 6524, 6502, 8504, 8524 |
| Inputs | 1 | 1, 2 or 4 by PCI ID (`SetHardWareInfo()`); `m_nMaxChl` is always 4 |
| Frame layout | one input, four DMA buffers, a frame in four quarters | one DMA buffer per channel, a frame in two halves (`HLAF_SIZE`, register 50 + ch) |
| Toggle | register 32: 1 = top half done | register 32 + ch, per channel |
| Interrupt bits | 0 video, 8 audio | 0–3 video per channel, 8–11 audio per channel |
| Size limit | 4096 × 2160 | 1920 × 1080 (`MAX_VIDEO_HW_W/H`), 4 MiB buffers |
| Register 9 | reset value; the port set it to the largest quarter | 1920 × 1080 × 2 / 16 when `m_DeviceHW_Version` is 1 |
| Extra paths | CPU scalers for 17 sizes | NV12 to YUYV (`FillNV12ToYUY2`), deinterlace (`SetDeInterlace`), 90° rotation |
| Audio | HDMI, 4096-byte packets | the same per channel; some IDs have a line-in input (`m_nCurreMaxLineInChl`), which the driver doesn't expose |
| Names | `HUHDVideo`, `HUHDAudio`, DKMS `HwsUHDX1CaptureForLinux` | `HVideo`, `HAudio`, DKMS `HwsCaptureForLinux` |

Which PCI IDs are the VC41 and which the VC42 isn't known. The README compares the card to a quad-input capture card.

### The in-kernel `hws` driver

Linux 7.2 added `drivers/media/pci/hws` (Ben Hoff), which binds exactly the 13 PCI IDs this driver does. It's a rewrite of the same vendor code for these cards, so it's the best available reference for their hardware:
- per-channel halves, toggles and the address table, as here;
- register 9 at 1920 × 1080 × 2 / 16;
- device info from register 88 bits 15:8 (version) and 23:16 (sub-version), after the accepted fix "media: hws: fix device info register field masks";
- "only init channels the device actually has" (accepted, 2026-08);
- "wait for IRQ handler before returning buffers" (accepted, 2026-08);
- HDMI audio for these cards in review (v3, 2026-06), with a newer revision on `github.com/benhoff/hws` branch `audio-upstream-v20-source-rewrite` (sets `SNDRV_PCM_INFO_BATCH`).

When a VC12-4K change touches a register or the DMA path, the port checks what `hws` does on these cards and follows it.

The two drivers also compete: on 7.2+ kernels both `hws` and `HwsCapture` claim these cards, and whichever loads first binds. See decision D1.

## Decisions

| ID | Decision | Choice |
|---|---|---|
| D1 | The in-kernel `hws` driver claims the same cards on 7.2+ | `install.sh` writes `/etc/modprobe.d/hws-capture.conf` with `blacklist hws` and a comment saying why and how to remove it; `uninstall.sh` removes it. The README says how to use `hws` instead. |
| D2 | Zero-copy (VC12 PR #30) | Left out. It depends on the VC12-4K quarter layout and was tested only there. `hws` does zero-copy on these cards; that's the better source for it later. |
| D3 | The hue control | Kept. The VC12-4K ignores hue on HDMI; these cards include SDI models, and whether they ignore it is unknown. |
| D4 | Fixes that depend on VC12-4K hardware behaviour | Ported only as the general bug fix (bounds checks, locking), not with VC12-4K values. Listed per PR below. |
| D5 | Per-channel state | Every per-channel fix applies to all channels the PCI ID has (`m_nCurreMaxVideoChl`), not only channel 0. |
| D6 | Versioning | `PACKAGE_VERSION` becomes 1.1.0 in the packaging PR, as on the VC12-4K. |
| D7 | Docs | Each PR's description carries its caveats. `docs/PORT.md` maps each VC12-4K commit to its port and lists the unknowns, so testers know what to check. |

## The PR series

Branches: `upstream/1-audio-batch` … `upstream/6-packaging` on a fork of this repository, each on top of the previous. Each PR's description states the merge order, the VC12-4K PR it ports, what's left out, and "Not tested on VC41/VC42 hardware".

VC12-4K commits that only record VC12-4K results (`docs: record …`) aren't ported. The VC12-4K test scripts are ported where they don't depend on that card (`framecheck.py`, the build check, the unit tests).

### PR 1: audio BATCH (VC12 #26)

- `f40a4d5` mark the PCM as BATCH and align periods to the 4096-byte DMA packets.

Applies cleanly to this driver and builds (checked 2026-10-20). Same packet size (`MAX_DMA_AUDIO_PK_SIZE`), same ALSA code, one capture PCM per channel. The line-in input some IDs have isn't exposed as a PCM by this driver.

Unknown: whether these cards' audio shows the PipeWire crackle the VC12-4K did. The fix is correct for any device that delivers audio in fixed packets.

### PR 2: frame delivery (VC12 #27)

- `890ff94` status thread sleeps interruptibly when idle;
- `a319e19` frame-queue buffers with `kvzalloc`, no page reservation;
- `2d8e283` never program a DMA length larger than the buffer (the VC12-4K's 4096 × 2160 sizing becomes a bound against `m_MaxHWVideoBufferSize` here; D4);
- `23392ec` per-queue locking, so a blocking DQBUF can't hang other ioctls;
- `49080f5` refuse format changes while buffers exist; check sizes before copying;
- `8f5cb58` `stop_streaming` waits for buffers being filled;
- `68f0c92` timestamps at the frame-end interrupt, sequence numbers per frame;
- `7cc4188` each frame delivered once per consumer, copied without interrupts disabled;
- `7243fdf` the frame-delivery check (`tests/framecheck.py`), with the device found by driver name `HwsCapture`.

Adapt: per-channel state for every channel (D5). Halves, not quarters: "frame end" is the second half's toggle.

### PR 3: input information (VC12 #28)

- `c89526e` unique `bus_info` per channel, correct 720 × 576 mode, no unimplemented `read()`;
- `00f59a5`, `f3da7f7` measured input frame rate, in frame periods, reported in `G_PARM`;
- `ec373f1` picture controls through the control framework (hue kept, D3);
- `a9ef468` the input's native size offered first and followed when idle;
- `c466a2f` real frame intervals and per-consumer rates through `S_PARM`;
- `5af2e2b`, `9f6cab6`, `4a87a38` DV timings, signal status, source-change events, `log_status`, and only deliverable timings listed;
- `182c304` close a handle's queue before counting it closed;
- `483648e` re-initialise the card after system suspend;
- `b8cb4e6` `V4L2_CID_DV_RX_POWER_PRESENT`;
- `8def62a` the build check against every installed kernel.

Adapt: the DV timings list is bounded by 1920 × 1080 and this driver's mode table. Register 110 (input rate) is read only where `hws` reads it. Interlaced inputs stay supported: these cards deinterlace (`SetDeInterlace`), so timings for interlaced inputs aren't dropped as on the VC12-4K.

Not ported: `1a794ea` dropping hue (D3).

### PR 4: capture rework (VC12 #29)

- `cae50c6` copy each half straight into app buffers from a threaded IRQ (replaces the per-channel tasklets);
- `5bd61fb` probe and remove ordering, error paths, interrupt flags;
- `fa5b301` debugfs status (per channel);
- `479286e` report the card's frame rate when no measurement exists;
- `12e91c5` black frames while the source uses HDCP (register 8, bit ch, as in `hws`);
- `46f7ec9` 500 µs pause in the start sequence;
- `96dd3f1` colorimetry in the format (`hws` reports full range for these cards);
- `ddc7606` rate-limited `LOG_STATUS`;
- `2ef336a` 50 ms input poll;
- `1f3e39a` silence while the card sends no audio, per channel.

Adapt: the copy path keeps the NV12, deinterlace and rotation conversions where this driver applies them.

Not ported: `8a67155`, `df0a168`, `bf69f64`, `7df0340` (the DMA canary and the register 9 overrun fix). The canary was a VC12-4K investigation tool, and the overrun was measured only there. This driver already writes register 9 as `hws` does. The PR names this as an unknown.

### PR 5: audit fixes (VC12 #31, without the zero-copy items)

Ported:
- `af7a1eb` debug-only DMA checks behind `debug_dma` (the debugfs snapshots; no canary);
- `9a7d8c0` no card re-initialisation from the atomic PCM trigger;
- `60ed9a7` no audio into a stopped stream; SUSPEND treated as STOP;
- `fed9220`, `6e4fd45`, `78484d4` unregister before teardown, free on last close, stop the status thread on probe failure, wake blocked readers on removal;
- `ae6e63e` acknowledge exactly the interrupt bits that are set (all channels' video and audio bits);
- `693863f` bounded busy wait after stopping;
- `1382cf8` freezable status thread;
- `41c0d63` don't read an absent card (0xFFFFFFFF) as HDCP;
- `e02e347` leave Relaxed Ordering to the PCI core;
- `dd669a0` no DMA sync calls on coherent buffers;
- `8377ac9` fail a frame whose half may have been overwritten during the copy;
- `4a07d5e` recover a card that lost its run state;
- `a4311ca` stop video DMA with a readback before releasing buffers;
- `07860d0` stop the engine for an input-size change while capturing;
- `f3c5ded` drop stale audio packets after an audio start (unknown whether these cards send them; dropping two 21 ms packets is harmless if they don't);
- `583a751` the stale bottom-half test knob;
- `0f2c6c7`, `aeeb157`, `d4f6c40`, `0499165` dead code and include cleanup;
- `d7cea32` source-only DKMS installs in `tools/dkms-install.sh`;
- test scripts that don't depend on the VC12-4K: `4e12ea3` (switch test, restart counter), `87c6930`, `7b4c70a`, `b9f1c2c`, `1fdf4cb`, `e88d445`, `9dda857`.

Also, from `hws`: probe only the channels the PCI ID has ("only init channels the device actually has").

Not ported: `d6e23f9`, `f772cef`, `8fa4801` (zero-copy, D2); `ff93168` and `ace5f67` (VC12-4K GPU-capture tests).

### PR 6: installer, CI and docs (VC12 #32)

- `d3f0412` `.gitignore`, `ccflags-y`, no `src/load.sh`;
- `bff3f78` probe tools check the device first;
- `3be8a4d` pure calculations into a header with unit tests (`8ade178`); the quarter maths becomes the halves maths;
- `f4732c7` detect backported kernel APIs; build without dma-contig;
- `38c1b72` CI against nine distributions' kernel headers;
- `8fef480`, `d210a33`, `e3722c2`, `89749a5` one DKMS install path, one uninstall, missing-module hints, Secure Boot handling; plus D1's `hws` blacklist;
- `bab04c4` README as a user guide, with a "Status of this port" section: what was ported, that it's untested on hardware, and how to report results;
- `e2d598a` changelog, security policy, release notes for 1.1.0 (marked untested);
- `docs/PORT.md` (D7).

Not ported: `04b43fe`, `8ca8a40` (the VC12-4K's 4K scalers; this driver has none at 4K).

## Verification

None of this runs on a card. Each PR must pass, before it's opened:
1. **Build:** the module builds without new warnings for every installed kernel here (7.2.x) and in the nine-distribution CI matrix (5.14 to 7.2) once PR 6's `tools/ci-build.sh` exists. Earlier PRs use that script locally.
2. **Unit tests** (from PR 6 on, and run against earlier PRs locally): ASan and UBSan clean.
3. **checkpatch:** no new kinds of finding (`--show-types`) per file. More instances of an existing kind are allowed where the new line follows the surrounding vendor style, as the VC12-4K commits do; matching the VC12-4K diff matters more than restyling.
4. **Review against `hws`:** each register write and DMA change is compared with `drivers/media/pci/hws` and noted in `docs/PORT.md`.
5. **Diff review:** the PR's diff is read against the VC12-4K commit it ports, and each difference is explained in `docs/PORT.md`.
6. **Stacking:** each branch contains the previous one, and the series ends at the same tree as `port/vc12-fixes`.

## Unknowns for testers

Each goes in `docs/PORT.md` and in the PR that touches it:
- whether audio crackles under PipeWire before PR 1;
- whether these cards send stale audio packets after an enable;
- whether hue has any effect (HDMI and SDI models);
- the colour range delivered;
- whether register 9 at 1080p stops runs past the buffer as it does on the VC12-4K at 4K;
- register 110 (input rate) on each FPGA version;
- interlaced input after the capture rework (deinterlace path);
- the NV12 path on boards with `support_yv12`;
- which PCI IDs are the VC41 and the VC42.

## Ground rules

- Don't change the licence or GloriousEggroll's README preface.
- PRs go to `GloriousEggroll/AVMATRIX-VC41-VC42-CAPTURE` from a fork under the contributor's account. The contributor opens them; descriptions are drafted for the contributor to edit.
- Push only when asked.
