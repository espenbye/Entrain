import AVFoundation
#if os(macOS)
import CoreAudio
#endif

/// Whether sound goes to headphones. Binaural beats need a separate carrier
/// in each ear, so over speakers the session mutes them and says why.
///
/// On iPhone and watch the audio session names the output port. The Mac
/// has no audio session: the default output device's transport type tells
/// external speakers apart, and the built-in device's data source says
/// whether the jack is in use. Anything unclear counts as headphones, so a
/// wrong guess costs a caption rather than the tone.
@MainActor
final class OutputRoute {
    private let onChange: @MainActor (Bool) -> Void
    #if os(macOS)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listener: AudioObjectPropertyListenerBlock = { _, _ in }
    #else
    private var observer: NSObjectProtocol?
    #endif

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        #if os(macOS)
        listener = { _, _ in Task { @MainActor [weak self] in self?.changed() } }
        var address = Self.defaultDevice
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        listen(to: Self.currentDevice)
        #else
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.changed() }
        }
        #endif
    }

    isolated deinit {
        #if os(macOS)
        var address = Self.defaultDevice
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        listen(to: AudioObjectID(kAudioObjectUnknown))
        #else
        observer.map(NotificationCenter.default.removeObserver)
        #endif
    }

    private func changed() {
        #if os(macOS)
        listen(to: Self.currentDevice)
        #endif
        onChange(Self.headphones)
    }

    #if os(macOS)
    private static let defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )
    private static let transportType = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )
    private static let dataSource = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDataSource,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
    )

    private static var currentDevice: AudioObjectID {
        read(AudioObjectID(kAudioObjectSystemObject), defaultDevice) ?? AudioObjectID(kAudioObjectUnknown)
    }

    /// The built-in device is one object for the speakers and the jack;
    /// plugging in changes its data source, not the default device.
    private func listen(to newDevice: AudioObjectID) {
        guard newDevice != device else { return }
        var address = Self.dataSource
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
        device = newDevice
        if device != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
    }

    static var headphones: Bool {
        let device = currentDevice
        guard device != kAudioObjectUnknown, let transport: UInt32 = read(device, transportType) else { return true }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // 'hdpn' is the jack; 'ispk' the internal speakers.
            return read(device, dataSource) == UInt32(0x6864_706E)
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeAirPlay:
            return false
        default:
            return true
        }
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
    #else
    /// Speakers, the earpiece, a TV and a car are not headphones; every
    /// other port (wired, Bluetooth, USB) plays into the ears.
    private static let speakers: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver, .HDMI, .airPlay, .carAudio]

    static var headphones: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return !outputs.contains { speakers.contains($0.portType) }
    }
    #endif
}
