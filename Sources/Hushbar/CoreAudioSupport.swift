import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? { "\(operation) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
}

func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func read<T>(_ selector: AudioObjectPropertySelector, default initial: T) throws -> T {
        var address = propertyAddress(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutableBytes(of: &value) { bytes in
            try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, bytes.baseAddress!), "Reading property")
        }
        return value
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector, element: T) throws -> [T] {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "Reading property size")
        var values = [T](repeating: element, count: Int(size) / MemoryLayout<T>.stride)
        try values.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, base), "Reading property")
        }
        return values
    }

    func readString(_ selector: AudioObjectPropertySelector) throws -> String {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value), "Reading string property")
        return value?.takeRetainedValue() as String? ?? ""
    }
}

func defaultOutputDeviceUID() throws -> String {
    let device: AudioDeviceID = try AudioObjectID.system.read(
        kAudioHardwarePropertyDefaultOutputDevice, default: AudioDeviceID(kAudioObjectUnknown))
    return try device.readString(kAudioDevicePropertyDeviceUID)
}

func deviceID(forUID uid: String) throws -> AudioDeviceID {
    let devices = try AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, element: AudioDeviceID(0))
    guard let match = devices.first(where: { (try? $0.readString(kAudioDevicePropertyDeviceUID)) == uid }) else {
        throw CoreAudioError(operation: "Finding output device", status: kAudioHardwareBadDeviceError)
    }
    return match
}

/// A Core Audio property listener that stops listening when released.
final class PropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, onChange: @escaping () -> Void) {
        self.object = object
        address = propertyAddress(selector)
        block = { _, _ in onChange() }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block)
        guard status == noErr else { return nil }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }
}
