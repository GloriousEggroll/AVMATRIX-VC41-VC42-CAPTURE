/*
 * Tests for src/hws_calc.h, the driver's pure calculations. Built with ASan
 * and UBSan by the Makefile; exits non-zero if a check fails.
 */
#include <stdio.h>
#include <stdlib.h>
#include "hws_calc.h"

static int failures;

#define CHECK(cond, ...) do {						\
	if (!(cond)) {							\
		fprintf(stderr, "%s:%d: %s: ", __FILE__, __LINE__, #cond);	\
		fprintf(stderr, __VA_ARGS__);				\
		fputc('\n', stderr);					\
		failures++;						\
	}								\
} while (0)

/* Every input size the driver accepts: up to 1920 x 1080 (MAX_VIDEO_HW_W/H). */
#define MAX_W 1920
#define MAX_H 1080
/* A channel's DMA buffer, less the audio ring at its end (MAX_MM_VIDEO_SIZE, MAX_AUDIO_CAP_SIZE). */
#define VIDEO_ROOM (0x400000 - 10 * 1024)

/* bytes in one frame of output format @fmt, as SetVideoFormteSize() sizes it */
static int frame_bytes(int w, int h, int fmt)
{
	if (fmt == 0)
		return w * h * 2;
	if (fmt == 1)
		return w * h * 12 / 8;
	return w * h * 5 / 4;
}

static void test_half_sizes(void)
{
	int w, h, fmt, hf, down;

	/* 1920 x 1080 YUYV: half the frame, rounded down to whole 2 KiB blocks */
	CHECK(hws_half_sizes(1920, 1080, 0, &hf, &down) == 0, "1080p rejected");
	CHECK(hf == 2072576 && down == 2074624, "1080p: %d %d", hf, down);

	for (fmt = 0; fmt <= 2; fmt++)
		for (w = 2; w <= MAX_W; w += 2)
			for (h = 2; h <= MAX_H; h += 2) {
				if (hws_half_sizes(w, h, fmt, &hf, &down) < 0) {
					CHECK(0, "%dx%d format %d rejected", w, h, fmt);
					continue;
				}
				CHECK(hf % HWS_DMA_BLOCK == 0, "%dx%d format %d: first half not whole blocks",
				      w, h, fmt);
				CHECK(hf + down == frame_bytes(w, h, fmt), "%dx%d format %d: halves %d + %d",
				      w, h, fmt, hf, down);
				CHECK(hf <= down, "%dx%d format %d: first half larger", w, h, fmt);
				/* SetVideoFormteSize() refuses a frame that doesn't fit; none should */
				CHECK(hf + down <= VIDEO_ROOM, "%dx%d format %d: %d bytes don't fit",
				      w, h, fmt, hf + down);
				if (failures > 20)
					return;
			}
}

static u64 ns_for(u32 num, u32 den)
{
	return (u64)num * NSEC_PER_SEC / den;
}

static void test_snap(void)
{
	int i;

	/* each standard interval snaps to itself, with either tolerance */
	for (i = 0; i < (int)HWS_N_STD_INTERVALS; i++) {
		u64 ns = ns_for(hws_std_intervals[i][0], hws_std_intervals[i][1]);

		CHECK(hws_snap_interval(ns, 200) == i, "standard %d doesn't snap to itself", i);
		/* 0.02%: the 1000/1001 pairs are only 0.1% apart, so stay well inside that */
		CHECK(hws_snap_interval(ns + ns / 5000, 200) == i, "standard %d +0.02%% lost", i);
	}
	/* 59.94 and 60 stay apart at 0.5% */
	i = hws_snap_interval(16683350, 200);
	CHECK(i >= 0 && hws_std_intervals[i][0] == 1001 && hws_std_intervals[i][1] == 60000, "59.94 -> %d", i);
	i = hws_snap_interval(16666667, 200);
	CHECK(i >= 0 && hws_std_intervals[i][0] == 1 && hws_std_intervals[i][1] == 60, "60 -> %d", i);
	/* nothing standard near 45 fps or 75 fps */
	CHECK(hws_snap_interval(ns_for(1, 45), 200) == -1, "45 fps snapped");
	CHECK(hws_snap_interval(ns_for(1, 75), 50) == -1, "75 fps snapped at 2%%");
	/* the card's whole-fps register, 2%: 59 fps reads as 59.94 */
	i = hws_snap_interval(ns_for(1, 59), 50);
	CHECK(i >= 0 && hws_std_intervals[i][1] == 60000, "59 fps register -> %d", i);
	/* 1% off misses at 0.5% but not at 2% */
	CHECK(hws_snap_interval(ns_for(1, 60) * 101 / 100, 200) == -1, "1%% off snapped at 0.5%%");
	CHECK(hws_snap_interval(ns_for(1, 60) * 101 / 100, 50) >= 0, "1%% off missed at 2%%");
}

static void test_rate_window(void)
{
	struct hws_rate_win r = { 0 };
	u64 t = 1000000000ULL, iv = 0, step = 16666667;
	int i;

	CHECK(hws_rate_frame_end(&r, t) == 0, "first frame gave a rate");
	for (i = 1; i <= 61 && !iv; i++)
		iv = hws_rate_frame_end(&r, t + i * step);
	CHECK(iv >= step - 2 && iv <= step + 2, "steady 60 fps measured %llu", (unsigned long long)iv);

	/* a missed frame end (one 33 ms gap) still counts as two frames */
	r = (struct hws_rate_win){ 0 };
	iv = 0;
	hws_rate_frame_end(&r, t);
	for (i = 1; i <= 70 && !iv; i++) {
		if (i == 30)
			continue;
		iv = hws_rate_frame_end(&r, t + i * step);
	}
	CHECK(iv >= step - 2 && iv <= step + 2, "60 fps with a gap measured %llu", (unsigned long long)iv);

	/* more than 200 ms between frame ends restarts the window */
	r = (struct hws_rate_win){ 0 };
	hws_rate_frame_end(&r, t);
	hws_rate_frame_end(&r, t + step);
	CHECK(hws_rate_frame_end(&r, t + step + 250000000ULL) == 0, "250 ms gap gave a rate");
	CHECK(r.frames == 0 && r.start == t + step + 250000000ULL, "250 ms gap didn't restart");

	/* 25 fps, the slowest PAL rate */
	r = (struct hws_rate_win){ 0 };
	iv = 0;
	step = 40000000;
	hws_rate_frame_end(&r, t);
	for (i = 1; i <= 30 && !iv; i++)
		iv = hws_rate_frame_end(&r, t + i * step);
	CHECK(iv >= step - 2 && iv <= step + 2, "25 fps measured %llu", (unsigned long long)iv);
}

static void test_closest(void)
{
	u64 cand[] = { 16683333, 16666667, 20000000 };	/* 59.94, 60, 50 */

	CHECK(hws_closest_interval(cand, 3, 16666667) == 1, "60 not picked");
	CHECK(hws_closest_interval(cand, 3, 16683350) == 0, "59.94 not picked");
	/* the 1% is of the wanted interval */
	CHECK(hws_closest_interval(cand, 3, 20000000ULL * 102 / 100) == -1, "2%% off accepted");
	CHECK(hws_closest_interval(cand, 3, 20000000ULL * 199 / 200) == 2, "0.5%% off rejected");
	CHECK(hws_closest_interval(cand, 0, 16666667) == -1, "no candidates gave a match");
}

int main(void)
{
	test_half_sizes();
	test_snap();
	test_rate_window();
	test_closest();
	if (failures) {
		fprintf(stderr, "test_calc: %d failed\n", failures);
		return 1;
	}
	puts("test_calc: all passed");
	return 0;
}
