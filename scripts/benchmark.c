#include "ClackAudio.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC_RAW, &t);
    return t.tv_sec * 1e6 + t.tv_nsec / 1e3;
}
static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
int main(void) {
    ClackMixer *m = clack_create(48000);
    float sample[8192], left[128], right[128];
    for (unsigned i = 0; i < 8192; ++i) sample[i] = (i % 48) * 0.001f;
    for (unsigned i = 0; i < 12; ++i) clack_load(m, i, sample, 8192);
    double timings[10000], enqueue[10000];
    for (unsigned i = 0; i < 10000; ++i) {
        // Sustained worst case: all 64 voices continuously active.
        double start = now();
        clack_trigger(m, i % 50, false);
        enqueue[i] = now() - start;
        start = now();
        clack_render(m, left, right, 128);
        timings[i] = now() - start;
    }
    qsort(timings, 10000, sizeof(double), compare);
    qsort(enqueue, 10000, sizeof(double), compare);
    printf("Event enqueue p99: %.2f µs\n", enqueue[9900]);
    printf("128-frame render with 64 overlapping voices: p50 %.2f µs, p99 %.2f µs\n", timings[5000], timings[9900]);
    printf("Audio buffer budget at 48 kHz: 2666.67 µs (2.67 ms)\n");
    printf("Dropped events: %llu\n", (unsigned long long)clack_dropped_events(m));
    clack_destroy(m);
}
