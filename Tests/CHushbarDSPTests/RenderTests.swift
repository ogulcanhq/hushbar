import CHushbarDSP
import CoreAudio
import XCTest

final class RenderTests: XCTestCase {
    /// Runs one render with the given streams and returns the output streams.
    /// Each stream is (channel count, interleaved samples).
    private func render(
        gain: OpaquePointer,
        input: [(channels: UInt32, samples: [Float])],
        output: [(channels: UInt32, frames: Int)]
    ) -> [[Float]] {
        func allocate(_ samples: [Float]) -> UnsafeMutableBufferPointer<Float> {
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
            _ = buffer.initialize(from: samples)
            return buffer
        }
        let inputBuffers = input.map { allocate($0.samples) }
        let outputBuffers = output.map { allocate([Float](repeating: 99, count: Int($0.channels) * $0.frames)) }
        let inputList = AudioBufferList.allocate(maximumBuffers: max(input.count, 1))
        let outputList = AudioBufferList.allocate(maximumBuffers: max(output.count, 1))
        defer {
            (inputBuffers + outputBuffers).forEach { $0.deallocate() }
            inputList.unsafeMutablePointer.deallocate()
            outputList.unsafeMutablePointer.deallocate()
        }

        inputList.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(input.count)
        for (index, buffer) in inputBuffers.enumerated() {
            inputList[index] = AudioBuffer(
                mNumberChannels: input[index].channels,
                mDataByteSize: UInt32(buffer.count * 4),
                mData: buffer.baseAddress)
        }
        for (index, buffer) in outputBuffers.enumerated() {
            outputList[index] = AudioBuffer(
                mNumberChannels: output[index].channels,
                mDataByteSize: UInt32(buffer.count * 4),
                mData: buffer.baseAddress)
        }

        hb_render(gain, inputList.unsafePointer, outputList.unsafeMutablePointer)
        return outputBuffers.map(Array.init)
    }

    private func makeGain(_ value: Float) -> OpaquePointer {
        hb_gain_create(value)
    }

    func testAppliesGainToInterleavedStereo() {
        let gain = makeGain(0.5)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [1, -1, 0.5, -0.5])], output: [(2, 2)])
        XCTAssertEqual(out[0], [0.5, -0.5, 0.25, -0.25])
        XCTAssertEqual(hb_gain_input_peak(gain), 1)
        XCTAssertEqual(hb_gain_output_peak(gain), 0.5)
    }

    func testZeroGainSilencesOutput() {
        let gain = makeGain(0)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [1, 1, 1, 1])], output: [(2, 2)])
        XCTAssertEqual(out[0], [0, 0, 0, 0])
    }

    func testGainChangeRampsAcrossOneBufferThenHolds() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        hb_gain_set(gain, 0)
        let first = render(gain: gain, input: [(1, [1, 1, 1, 1])], output: [(1, 4)])
        XCTAssertEqual(first[0], [0.75, 0.5, 0.25, 0])
        let second = render(gain: gain, input: [(1, [1, 1])], output: [(1, 2)])
        XCTAssertEqual(second[0], [0, 0])
    }

    func testReadsTapFromLastStreamNotDeviceMic() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let mic: (channels: UInt32, samples: [Float]) = (1, [0.9, 0.9])
        let out = render(gain: gain, input: [mic, (2, [0.1, 0.2, 0.3, 0.4])], output: [(2, 2)])
        XCTAssertEqual(out[0], [0.1, 0.2, 0.3, 0.4])
    }

    func testAcceptsNonInterleavedTap() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(1, [0.1, 0.2]), (1, [0.3, 0.4])], output: [(2, 2)])
        XCTAssertEqual(out[0], [0.1, 0.3, 0.2, 0.4])
    }

    func testExtraOutputChannelsAreSilent() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [0.1, 0.2])], output: [(4, 1)])
        XCTAssertEqual(out[0], [0.1, 0.2, 0, 0])
    }

    func testSplitsStereoAcrossSeparateOutputStreams() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [0.1, 0.2])], output: [(1, 1), (1, 1), (1, 1)])
        XCTAssertEqual(out[0], [0.1])
        XCTAssertEqual(out[1], [0.2])
        XCTAssertEqual(out[2], [0])
    }

    func testMixesDownForMonoOutput() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [0.25, 0.75])], output: [(1, 1)])
        XCTAssertEqual(out[0], [0.5])
    }

    func testMissingInputWritesSilence() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [], output: [(2, 2)])
        XCTAssertEqual(out[0], [0, 0, 0, 0])
    }

    func testShortInputPadsOutputWithSilence() {
        let gain = makeGain(1)
        defer { hb_gain_destroy(gain) }
        let out = render(gain: gain, input: [(2, [0.5, 0.5])], output: [(2, 2)])
        XCTAssertEqual(out[0], [0.5, 0.5, 0, 0])
    }
}
