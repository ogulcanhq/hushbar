#include "hushbar_dsp.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct HBGain {
    _Atomic float target;
    _Atomic float input_peak;
    _Atomic float output_peak;
    float current; // Audio thread only.
};

HBGain *hb_gain_create(float initial) {
    HBGain *gain = calloc(1, sizeof(HBGain));
    if (gain) {
        atomic_init(&gain->target, initial);
        atomic_init(&gain->input_peak, 0.0f);
        atomic_init(&gain->output_peak, 0.0f);
        gain->current = initial;
    }
    return gain;
}

void hb_gain_destroy(HBGain *gain) { free(gain); }

void hb_gain_set(HBGain *gain, float value) {
    atomic_store_explicit(&gain->target, value, memory_order_relaxed);
}

float hb_gain_input_peak(const HBGain *gain) {
    return atomic_load_explicit(&gain->input_peak, memory_order_relaxed);
}

float hb_gain_output_peak(const HBGain *gain) {
    return atomic_load_explicit(&gain->output_peak, memory_order_relaxed);
}

typedef struct {
    const float *left;
    const float *right;
    UInt32 stride;
    UInt32 frames;
} TapStream;

static TapStream find_tap_stream(const AudioBufferList *input) {
    TapStream tap = {NULL, NULL, 1, 0};
    if (!input || input->mNumberBuffers == 0) return tap;

    const UInt32 count = input->mNumberBuffers;
    const AudioBuffer *last = &input->mBuffers[count - 1];
    if (!last->mData || last->mNumberChannels == 0) return tap;

    if (last->mNumberChannels >= 2) {
        tap.left = last->mData;
        tap.right = tap.left + 1;
        tap.stride = last->mNumberChannels;
    } else if (count >= 2 && input->mBuffers[count - 2].mNumberChannels == 1 &&
               input->mBuffers[count - 2].mData) {
        tap.left = input->mBuffers[count - 2].mData;
        tap.right = last->mData;
    } else {
        tap.left = last->mData;
        tap.right = last->mData;
    }
    tap.frames = last->mDataByteSize / (UInt32)sizeof(float) / last->mNumberChannels;
    return tap;
}

void hb_render(HBGain *gain, const AudioBufferList *input, AudioBufferList *output) {
    if (!output || output->mNumberBuffers == 0) return;

    const TapStream tap = find_tap_stream(input);
    const float start = gain->current;
    const float target = atomic_load_explicit(&gain->target, memory_order_relaxed);

    UInt32 total_channels = 0;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        total_channels += output->mBuffers[b].mNumberChannels;
    }
    const int mono_output = total_channels == 1;

    float input_peak = 0.0f;
    for (UInt32 f = 0; f < tap.frames; f++) {
        const float l = fabsf(tap.left[f * tap.stride]);
        const float r = fabsf(tap.right[f * tap.stride]);
        if (l > input_peak) input_peak = l;
        if (r > input_peak) input_peak = r;
    }

    float output_peak = 0.0f;
    UInt32 channel = 0;
    for (UInt32 b = 0; b < output->mNumberBuffers; b++) {
        AudioBuffer *buffer = &output->mBuffers[b];
        const UInt32 channels = buffer->mNumberChannels;
        if (!buffer->mData || channels == 0) continue;

        float *samples = buffer->mData;
        const UInt32 frames = buffer->mDataByteSize / (UInt32)sizeof(float) / channels;
        const UInt32 copied = frames < tap.frames ? frames : tap.frames;
        const float step = copied > 0 ? (target - start) / (float)copied : 0.0f;

        for (UInt32 c = 0; c < channels; c++, channel++) {
            float *out = samples + c;
            if (channel >= 2 || !tap.left) {
                for (UInt32 f = 0; f < frames; f++) out[f * channels] = 0.0f;
                continue;
            }
            const float *in = channel == 0 ? tap.left : tap.right;
            for (UInt32 f = 0; f < copied; f++) {
                const float g = start + step * (float)(f + 1);
                const float sample = mono_output
                    ? 0.5f * (tap.left[f * tap.stride] + tap.right[f * tap.stride])
                    : in[f * tap.stride];
                const float value = sample * g;
                out[f * channels] = value;
                const float magnitude = fabsf(value);
                if (magnitude > output_peak) output_peak = magnitude;
            }
            for (UInt32 f = copied; f < frames; f++) out[f * channels] = 0.0f;
        }
    }

    gain->current = target;
    atomic_store_explicit(&gain->input_peak, input_peak, memory_order_relaxed);
    atomic_store_explicit(&gain->output_peak, output_peak, memory_order_relaxed);
}
