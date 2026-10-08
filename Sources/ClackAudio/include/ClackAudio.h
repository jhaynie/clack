#ifndef CLACK_AUDIO_H
#define CLACK_AUDIO_H
#include <stdint.h>
#include <stdbool.h>

typedef struct ClackMixer ClackMixer;
// macOS physical typing keys; Command/Control shortcuts and navigation are silent.
// Shift/Option remain allowed for capitals, punctuation, and accented input.
bool clack_should_sound(uint16_t key_code, uint64_t event_flags);
// Sample IDs: five presses, space/enter/backspace presses, then four releases.
ClackMixer *clack_create(double sample_rate);
void clack_destroy(ClackMixer *mixer);
// Load only while the audio engine is stopped. Samples are copied and owned here.
bool clack_load(ClackMixer *mixer, uint32_t id, const float *pcm, uint32_t frames);
void clack_set_volume(ClackMixer *mixer, float volume);
void clack_set_spatial(ClackMixer *mixer, float width);
void clack_set_enabled(ClackMixer *mixer, bool enabled);
void clack_set_releases(ClackMixer *mixer, bool enabled);
// Bounded, lock-free queue. Safe for concurrent input and preview producers.
bool clack_trigger(ClackMixer *mixer, uint16_t key_code, bool release);
// One audio consumer; no allocation, locks, file access, or ObjC/Swift work.
void clack_render(ClackMixer *mixer, float *left, float *right, uint32_t frames);
uint64_t clack_dropped_events(const ClackMixer *mixer);
#endif
