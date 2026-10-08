#include "ClackAudio.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define QUEUE_SIZE 256
#define VOICES 64
#define SAMPLES 12

typedef struct { float *pcm; uint32_t frames; } Sample;
typedef struct { uint16_t key; bool release; uint32_t epoch; } Event;
typedef struct { _Atomic uint64_t sequence; Event event; } Slot;
typedef struct {
    const Sample *sample;
    double cursor;
    float rate, left, right, gain;
    uint32_t delay_left, delay_right;
} Voice;

struct ClackMixer {
    Sample samples[SAMPLES];
    Slot queue[QUEUE_SIZE];
    _Atomic uint64_t write;
    uint64_t read;
    _Atomic uint64_t dropped;
    _Atomic uint32_t epoch;
    uint32_t rendered_epoch;
    _Atomic bool enabled, releases;
    _Atomic float volume, width;
    Voice voices[VOICES];
    float pans[128];
    uint32_t random, last_variant;
    double sample_rate;
    float current_volume;
};

static float clamp(float x, float lo, float hi) { return fminf(hi, fmaxf(lo, x)); }

bool clack_should_sound(uint16_t key_code, uint64_t event_flags) {
    const uint64_t control = UINT64_C(1) << 18, command = UINT64_C(1) << 20;
    if (event_flags & (control | command)) return false;
    // ANSI/ISO letters, numbers, punctuation, Tab, Enter, space, and Backspace.
    if (key_code <= 51) return true;
    switch (key_code) {
        // Numeric keypad, JIS punctuation, and forward delete.
        case 65: case 67: case 69: case 75: case 76: case 78: case 81:
        case 82: case 83: case 84: case 85: case 86: case 87: case 88:
        case 89: case 91: case 92: case 93: case 94: case 95: case 117:
            return true;
        default: return false;
    }
}

ClackMixer *clack_create(double sample_rate) {
    if (!isfinite(sample_rate) || sample_rate < 8000 || sample_rate > 192000) return NULL;
    ClackMixer *m = calloc(1, sizeof(*m));
    if (!m) return NULL;
    m->sample_rate = sample_rate;
    atomic_init(&m->write, 0); atomic_init(&m->dropped, 0);
    atomic_init(&m->epoch, 0); atomic_init(&m->enabled, true);
    atomic_init(&m->releases, true);
    atomic_init(&m->volume, 0.65f); atomic_init(&m->width, 0.8f);
    // Refuse a platform where the realtime controls would use hidden locks.
    if (!atomic_is_lock_free(&m->write) || !atomic_is_lock_free(&m->volume)) {
        free(m); return NULL;
    }
    m->current_volume = 0.65f; m->random = 0xC1AC;
    for (uint64_t i = 0; i < QUEUE_SIZE; ++i) atomic_init(&m->queue[i].sequence, i);
    const uint16_t rows[][14] = {
        {50,18,19,20,21,23,22,26,28,25,29,27,24,51},
        {48,12,13,14,15,17,16,32,34,31,35,33,30,42},
        {57,0,1,2,3,5,4,38,40,37,41,39,36,UINT16_MAX},
        {56,6,7,8,9,11,45,46,43,47,44,60,UINT16_MAX,UINT16_MAX},
        {59,58,55,UINT16_MAX,UINT16_MAX,UINT16_MAX,49,UINT16_MAX,UINT16_MAX,54,61,62,123,124}
    };
    for (unsigned row = 0; row < 5; ++row)
        for (unsigned col = 0; col < 14; ++col)
            if (rows[row][col] < 128) m->pans[rows[row][col]] = ((float)col / 13 * 2 - 1) * 0.85f;
    m->pans[49] = 0; m->pans[36] = 0.85f; m->pans[51] = 0.85f;
    m->pans[53] = -0.85f;
    m->pans[125] = 0.7f; m->pans[126] = 0.7f;
    return m;
}

void clack_destroy(ClackMixer *m) {
    if (!m) return;
    for (unsigned i = 0; i < SAMPLES; ++i) free(m->samples[i].pcm);
    free(m);
}

bool clack_load(ClackMixer *m, uint32_t id, const float *pcm, uint32_t frames) {
    if (!m || id >= SAMPLES || !pcm || !frames || frames > m->sample_rate * 5) return false;
    float *copy = malloc(frames * sizeof(float));
    if (!copy) return false;
    for (uint32_t i = 0; i < frames; ++i) copy[i] = isfinite(pcm[i]) ? clamp(pcm[i], -1, 1) : 0;
    free(m->samples[id].pcm);
    m->samples[id] = (Sample){copy, frames};
    return true;
}

void clack_set_volume(ClackMixer *m, float v) { atomic_store(&m->volume, isfinite(v) ? clamp(v,0,1) : 0); }
void clack_set_spatial(ClackMixer *m, float w) { atomic_store(&m->width, isfinite(w) ? clamp(w,0,1) : 0); }
void clack_set_releases(ClackMixer *m, bool e) { atomic_store(&m->releases, e); }
void clack_set_enabled(ClackMixer *m, bool e) {
    // Invalidate queued input so toggling back on never replays stale keystrokes.
    atomic_fetch_add(&m->epoch, 1);
    atomic_store(&m->enabled, e);
}

bool clack_trigger(ClackMixer *m, uint16_t key_code, bool release) {
    if (!atomic_load(&m->enabled) || (release && !atomic_load(&m->releases))) return false;
    const uint32_t epoch = atomic_load(&m->epoch);
    uint64_t pos = atomic_load_explicit(&m->write, memory_order_relaxed);
    Slot *slot;
    // Bound producer work even under contention; dropping is preferable to stalling input.
    for (unsigned attempt = 0; ; ++attempt) {
        slot = &m->queue[pos % QUEUE_SIZE];
        uint64_t seq = atomic_load_explicit(&slot->sequence, memory_order_acquire);
        int64_t difference = (int64_t)(seq - pos);
        if (difference < 0 || attempt >= 16) {
            atomic_fetch_add(&m->dropped, 1); return false;
        }
        if (difference == 0 && atomic_compare_exchange_weak_explicit(
            &m->write, &pos, pos + 1, memory_order_relaxed, memory_order_relaxed)) break;
        pos = atomic_load_explicit(&m->write, memory_order_relaxed);
    }
    slot->event = (Event){key_code, release, epoch};
    atomic_store_explicit(&slot->sequence, pos + 1, memory_order_release);
    return true;
}

static void start_voice(ClackMixer *m, Event event, float width) {
    m->random ^= m->random << 13; m->random ^= m->random >> 17; m->random ^= m->random << 5;
    // Four choices excluding the previous variant: no machine-gun repetition.
    uint32_t variant = (m->last_variant + 1 + m->random % 4) % 5;
    m->last_variant = variant;
    uint32_t sample = event.release ? 8 : variant;
    if (event.key == 49) sample = event.release ? 9 : 5;
    if (event.key == 36 || event.key == 76) sample = event.release ? 10 : 6;
    if (event.key == 51 || event.key == 117) sample = event.release ? 11 : 7;
    if (!m->samples[sample].frames) return;
    unsigned chosen = 0;
    double oldest = -1;
    for (unsigned i = 0; i < VOICES; ++i) {
        if (!m->voices[i].sample) { chosen = i; break; }
        if (m->voices[i].cursor > oldest) { oldest = m->voices[i].cursor; chosen = i; }
    }
    float pan = event.key < 128 ? m->pans[event.key] * width : 0;
    float angle = (pan + 1) * (float)M_PI / 4;
    uint32_t delay = (uint32_t)(fabsf(pan) * m->sample_rate * 0.00022);
    m->voices[chosen] = (Voice){
        .sample = &m->samples[sample], .cursor = 0,
        .rate = 0.99f + (m->random % 1000) * 0.00002f,
        .left = cosf(angle), .right = sinf(angle),
        .gain = event.release ? 0.62f : 0.94f + (m->random % 100) * 0.0012f,
        .delay_left = pan > 0 ? delay : 0, .delay_right = pan < 0 ? delay : 0
    };
}

static float read_sample(const Sample *s, double position) {
    if (position < 0 || position >= s->frames) return 0;
    uint32_t i = (uint32_t)position;
    float a = s->pcm[i], b = i + 1 < s->frames ? s->pcm[i+1] : 0;
    return a + (b - a) * (float)(position - i);
}

void clack_render(ClackMixer *m, float *left, float *right, uint32_t frames) {
    memset(left, 0, frames * sizeof(float)); memset(right, 0, frames * sizeof(float));
    bool enabled = atomic_load(&m->enabled);
    uint32_t epoch = atomic_load(&m->epoch);
    if (enabled && epoch != m->rendered_epoch) memset(m->voices, 0, sizeof(m->voices));
    m->rendered_epoch = epoch;
    float width = atomic_load(&m->width);
    for (unsigned n = 0; n < QUEUE_SIZE; ++n) {
        Slot *slot = &m->queue[m->read % QUEUE_SIZE];
        if (atomic_load_explicit(&slot->sequence, memory_order_acquire) != m->read + 1) break;
        Event event = slot->event;
        atomic_store_explicit(&slot->sequence, m->read + QUEUE_SIZE, memory_order_release);
        ++m->read;
        if (enabled && event.epoch == epoch) start_voice(m, event, width);
    }
    float target = enabled ? atomic_load(&m->volume) : 0;
    const float reflection_left = (float)(m->sample_rate * 0.008);
    const float reflection_right = (float)(m->sample_rate * 0.011);
    for (unsigned v = 0; v < VOICES; ++v) {
        Voice *voice = &m->voices[v];
        if (!voice->sample) continue;
        for (uint32_t i = 0; i < frames; ++i) {
            double l = voice->cursor - voice->delay_left, r = voice->cursor - voice->delay_right;
            left[i] += voice->gain * (voice->left * read_sample(voice->sample, l)
                        + width * 0.055f * read_sample(voice->sample, l - reflection_left));
            right[i] += voice->gain * (voice->right * read_sample(voice->sample, r)
                        + width * 0.055f * read_sample(voice->sample, r - reflection_right));
            voice->cursor += voice->rate;
            if (voice->cursor > voice->sample->frames + reflection_right + 32) {
                voice->sample = NULL; break;
            }
        }
    }
    const float step = (float)(1.0 / (m->sample_rate * 0.002));
    for (uint32_t i = 0; i < frames; ++i) {
        m->current_volume += clamp(target - m->current_volume, -step, step);
        float l = left[i] * m->current_volume, r = right[i] * m->current_volume;
        // Transparent below the knee; soft saturation protects fast overlapping chords.
        left[i] = fabsf(l) <= 0.8f ? l : copysignf(0.8f + 0.2f * tanhf((fabsf(l)-0.8f)*5), l);
        right[i] = fabsf(r) <= 0.8f ? r : copysignf(0.8f + 0.2f * tanhf((fabsf(r)-0.8f)*5), r);
    }
    if (!enabled && m->current_volume == 0) memset(m->voices, 0, sizeof(m->voices));
}

uint64_t clack_dropped_events(const ClackMixer *m) { return atomic_load(&m->dropped); }
