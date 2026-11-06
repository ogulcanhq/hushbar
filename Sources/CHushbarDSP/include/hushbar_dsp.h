#ifndef HUSHBAR_DSP_H
#define HUSHBAR_DSP_H

#include <CoreAudio/CoreAudioTypes.h>

/// Per-route state shared between the UI thread and the realtime audio thread.
typedef struct HBGain HBGain;

HBGain *hb_gain_create(float initial);
void hb_gain_destroy(HBGain *gain);

/// Safe to call from any thread. The change is ramped over the next buffer to avoid clicks.
void hb_gain_set(HBGain *gain, float value);

/// Absolute peak of the most recently rendered buffer, before and after gain.
float hb_gain_input_peak(const HBGain *gain);
float hb_gain_output_peak(const HBGain *gain);

/// Realtime safe. Copies the tap stream to the output with gain applied.
///
/// The tap is the last stream of `input`, because an aggregate device lists the
/// output device's own input streams (a headset mic, say) ahead of its taps.
/// All samples are Float32. Channels past the first two of the output get silence.
void hb_render(HBGain *gain, const AudioBufferList *input, AudioBufferList *output);

#endif
