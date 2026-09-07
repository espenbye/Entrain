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
    /// What CoreAudio hands back to `listener`. A weak box rather than self:
    /// the callback comes on CoreAudio's thread and may still be in flight
    /// while this route is going away. Released in deinit.
    private let box = Unmanaged.passRetained(WeakRoute())
    #else
    private var observer: NSObjectProtocol?
    #endif

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        #if os(macOS)
        box.takeUnretainedValue().route = self
        var address = Self.defaultDevice
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.listener, box.toOpaque())
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
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, Self.listener, box.toOpaque())
        listen(to: AudioObjectID(kAudioObjectUnknown))
        box.release()
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
    private final class WeakRoute: @unchecked Sendable {
        weak var route: OutputRoute?
    }

    /// The C listener pair is used rather than the block one: removing a
    /// block listener never unregisters a Swift closure, so listeners on
    /// old default devices would pile up.
    private static let listener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData else { return noErr }
        let box = Unmanaged<WeakRoute>.fromOpaque(clientData).takeUnretainedValue()
        Task { @MainActor in box.route?.changed() }
        return noErr
    }

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
            AudioObjectRemovePropertyListener(device, &address, Self.listener, box.toOpaque())
        }
        device = newDevice
        if device != kAudioObjectUnknown {
            AudioObjectAddPropertyListener(device, &address, Self.listener, box.toOpaque())
        }
    }

    static var headphones: Bool {
        let device = currentDevice
        guard device != kAudioObjectUnknown, let transport: UInt32 = read(device, transportType) else { return true }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            // 'hdpn' is the jack; 'ispk' the internal speakers.
            guard let source: UInt32 = read(device, dataSource) else { return true }
            return source == UInt32(0x6864_706E)
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
