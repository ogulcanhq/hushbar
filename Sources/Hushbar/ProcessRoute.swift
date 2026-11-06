import CHushbarDSP
import CoreAudio
import Foundation

/// Takes over one process's audio: a muted tap removes it from the normal output,
/// and a private aggregate device plays it back at the chosen gain.
/// Hushbar's taps and aggregates are private, so the system drops them if Hushbar exits.
final class ProcessRoute {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let gain: OpaquePointer
    private var isRunning = false

    init(processObject: AudioObjectID, outputUID: String, gain initialGain: Float) throws {
        guard let gain = hb_gain_create(initialGain) else {
            throw CoreAudioError(operation: "Allocating memory", status: -108)
        }
        self.gain = gain

        // Every stored property is set from here on, so a throw below runs deinit,
        // which releases whatever was created so far.
        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.name = "Hushbar Tap \(processObject)"
        description.isPrivate = true
        description.muteBehavior = .muted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating audio tap")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hushbar Route \(processObject)",
            kAudioAggregateDeviceUIDKey: "hushbar.route.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
            "Creating aggregate device")

        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                hb_render(gain, input, output)
            },
            "Creating audio callback")
    }

    deinit {
        if let ioProcID {
            if isRunning { AudioDeviceStop(aggregateID, ioProcID) }
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        hb_gain_destroy(gain)
    }

    func setGain(_ value: Float) {
        hb_gain_set(gain, value)
    }

    /// Runs the audio thread only while the process is playing, so an idle app costs nothing.
    func setRunning(_ running: Bool) throws {
        guard running != isRunning, let ioProcID else { return }
        if running {
            try check(AudioDeviceStart(aggregateID, ioProcID), "Starting audio")
        } else {
            try check(AudioDeviceStop(aggregateID, ioProcID), "Stopping audio")
        }
        isRunning = running
    }

    var inputPeak: Float { hb_gain_input_peak(gain) }
    var outputPeak: Float { hb_gain_output_peak(gain) }
}
