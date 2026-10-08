#include "ClackAudio.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>

static ClackMixer *mixer(void) {
    ClackMixer *m = clack_create(48000);
    assert(m);
    float samples[4096];
    for (int i = 0; i < 4096; ++i) samples[i] = 0.15f;
    for (unsigned id = 0; id < 12; ++id) assert(clack_load(m, id, samples, 4096));
    return m;
}
static float sum(float *x, int n) { float s = 0; for (int i = 0; i < n; ++i) s += x[i]; return s; }
static void silent(float *x, int n) { for (int i = 0; i < n; ++i) assert(x[i] == 0); }
static void safe(float *x, int n) { for (int i = 0; i < n; ++i) assert(isfinite(x[i]) && fabsf(x[i]) <= 1); }

static void onset_and_position(void) {
    float l[128], r[128];
    ClackMixer *m = mixer();
    assert(clack_trigger(m, 0, false)); // A: left
    clack_render(m,l,r,128);
    assert(l[0] > 0); // Begins at the next callback, without a scheduled delay.
    assert(sum(l,128) > sum(r,128) * 1.5f);
    clack_destroy(m);
    m = mixer();
    assert(clack_trigger(m,36,false)); // Enter: right
    clack_render(m,l,r,128);
    assert(r[0] > 0 && sum(r,128) > sum(l,128) * 1.5f);
    clack_destroy(m);
}
static void mono_and_chords(void) {
    float l[128],r[128];
    ClackMixer *m = mixer(); clack_set_spatial(m,0);
    assert(clack_trigger(m,0,false)); clack_render(m,l,r,128);
    for (int i = 0; i < 128; ++i) assert(fabsf(l[i]-r[i]) < 0.000001f);
    float single = sum(l,128); clack_destroy(m);
    m = mixer(); clack_set_spatial(m,0);
    for (unsigned key = 0; key < 4; ++key) assert(clack_trigger(m,key,false));
    clack_render(m,l,r,128);
    assert(sum(l,128) > single * 3.5f); // Earlier keys keep playing underneath new ones.
    clack_destroy(m);
}
static void mute_and_resume(void) {
    float l[512],r[512];
    ClackMixer *m = mixer();
    assert(clack_trigger(m,0,false)); clack_render(m,l,r,128);
    clack_set_enabled(m,false); assert(!clack_trigger(m,1,false));
    clack_render(m,l,r,512); clack_render(m,l,r,128); silent(l,128); silent(r,128);
    clack_set_enabled(m,true); clack_render(m,l,r,128); silent(l,128); silent(r,128);
    assert(clack_trigger(m,0,false));
    clack_set_enabled(m,false); clack_set_enabled(m,true);
    clack_render(m,l,r,128); silent(l,128); silent(r,128); // No stale queued input.
    assert(clack_trigger(m,0,false)); clack_render(m,l,r,128); assert(sum(l,128)>0);
    clack_set_enabled(m,false); clack_set_enabled(m,true);
    clack_render(m,l,r,128); silent(l,128); silent(r,128); // No stale active voices either.
    clack_destroy(m);
}
static void releases_and_spacebar(void) {
    float l[128],r[128];
    ClackMixer *m = mixer();
    clack_set_releases(m,false); assert(!clack_trigger(m,49,true));
    clack_set_releases(m,true); assert(clack_trigger(m,49,true));
    clack_render(m,l,r,128); assert(sum(l,128)>0); clack_destroy(m);
    m = mixer();
    float zeros[4096] = {0};
    for (unsigned i = 0; i < 5; ++i) assert(clack_load(m,i,zeros,4096));
    assert(clack_trigger(m,49,false)); clack_render(m,l,r,128); assert(l[0]>0);
    clack_destroy(m);
}
static void overload_and_recovery(void) {
    float l[128],r[128];
    ClackMixer *m = mixer();
    unsigned accepted = 0;
    for (unsigned i = 0; i < 10000; ++i) accepted += clack_trigger(m,0,false);
    assert(accepted>0 && accepted<10000 && clack_dropped_events(m)>0);
    clack_render(m,l,r,128); safe(l,128); safe(r,128);
    assert(clack_trigger(m,36,false));
    clack_destroy(m);
}
typedef struct { ClackMixer *m; _Atomic unsigned complete; _Atomic unsigned accepted; } Concurrent;
static void *producer(void *argument) {
    Concurrent *c = argument;
    for (unsigned i = 0; i < 10000; ++i)
        if (clack_trigger(c->m, i%50, false)) atomic_fetch_add(&c->accepted,1);
    atomic_fetch_add(&c->complete,1);
    return NULL;
}
static void concurrent_input_and_preview(void) {
    Concurrent c = {.m = mixer()};
    pthread_t threads[4];
    for (int i = 0; i < 4; ++i) assert(pthread_create(&threads[i],NULL,producer,&c)==0);
    float l[128],r[128];
    while (atomic_load(&c.complete)<4) { clack_render(c.m,l,r,128); safe(l,128); safe(r,128); }
    for (int i = 0; i < 4; ++i) pthread_join(threads[i],NULL);
    assert(atomic_load(&c.accepted)>0);
    assert(atomic_load(&c.accepted) + clack_dropped_events(c.m) == 40000);
    clack_render(c.m,l,r,128);
    assert(clack_trigger(c.m,49,false));
    clack_destroy(c.m);
}
static void bad_samples(void) {
    ClackMixer *m = mixer();
    float invalid[] = {NAN,INFINITY,-INFINITY,2,-2};
    assert(!clack_load(m,12,invalid,5));
    assert(!clack_load(m,0,NULL,5));
    assert(clack_load(m,5,invalid,5));
    clack_set_volume(m,NAN); clack_set_spatial(m,INFINITY);
    assert(clack_trigger(m,49,false));
    float l[128],r[128]; clack_render(m,l,r,128); safe(l,128); safe(r,128);
    clack_destroy(m);
}
static void typing_policy(void) {
    const uint64_t shift = UINT64_C(1)<<17, control = UINT64_C(1)<<18;
    const uint64_t option = UINT64_C(1)<<19, command = UINT64_C(1)<<20;
    assert(clack_should_sound(0,0)); // A
    assert(clack_should_sound(0,shift)); // Capital A
    assert(clack_should_sound(14,option)); // Option+E accented input
    assert(clack_should_sound(18,shift|option)); // Punctuation/alternate characters
    assert(clack_should_sound(48,0)); // Normal Tab
    assert(!clack_should_sound(48,command)); // Command+Tab
    assert(!clack_should_sound(8,command)); // Command+C
    assert(!clack_should_sound(9,command)); // Command+V
    assert(!clack_should_sound(0,control)); // Control+A
    for (unsigned i = 54; i <= 63; ++i) assert(!clack_should_sound(i,0)); // Modifiers
    for (unsigned i = 123; i <= 126; ++i) assert(!clack_should_sound(i,0)); // Arrows
    assert(!clack_should_sound(53,0)); // Escape
    assert(!clack_should_sound(122,0)); // F1
    assert(!clack_should_sound(64,0)); // F17
    assert(clack_should_sound(49,0)); // Space
    assert(clack_should_sound(36,0)); // Return
    assert(clack_should_sound(51,0)); // Backspace
    assert(clack_should_sound(117,0)); // Forward delete
    assert(clack_should_sound(82,0)); // Keypad zero
}
int main(void) {
    onset_and_position(); mono_and_chords(); mute_and_resume(); releases_and_spacebar();
    overload_and_recovery(); concurrent_input_and_preview(); bad_samples(); typing_policy();
    puts("Passed 8 audio behavior checks: onset, stereo/chords, mute, releases/spacebar, overload, concurrent input, invalid samples, typing/shortcut policy.");
}
