import Foundation
import Darwin

/// Optional macOS sensor API. Missing symbols or hardware return nil safely.
final class AmbientLightReader {
    private typealias CopyClient = @convention(c) () -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias ReadValue = @convention(c) (CFTypeRef, Int32) -> Double
    private let bezel = dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/BezelServices", RTLD_LAZY)
    private let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private var client: CFTypeRef?
    func readLux() -> Double? {
        guard let bezel, let io,
              let copyClientSymbol = dlsym(bezel, "ALCALSCopyALSServiceClient"),
              let copyEventSymbol = dlsym(io, "IOHIDServiceClientCopyEvent"),
              let readSymbol = dlsym(io, "IOHIDEventGetFloatValue") else { return nil }
        if client == nil { client = unsafeBitCast(copyClientSymbol, to: CopyClient.self)()?.takeRetainedValue() }
        guard let client, let event = unsafeBitCast(copyEventSymbol, to: CopyEvent.self)(client, 12, 0, 0)?.takeRetainedValue() else { return nil }
        let lux = unsafeBitCast(readSymbol, to: ReadValue.self)(event, 12 << 16)
        return lux.isFinite && lux >= 0 ? lux : nil
    }
    deinit {
        client = nil
        if let bezel { dlclose(bezel) }
        if let io { dlclose(io) }
    }
}

struct MirrorLightState {
    private(set) var on = false
    private var darkSamples = 0
    private var brightSamples = 0
    mutating func update(lux: Double?, imageBrightness: Double) -> Bool {
        let dark = lux.map { $0 < 30 } ?? (imageBrightness < 85)
        let bright = lux.map { $0 > 80 } ?? false
        darkSamples = dark ? darkSamples + 1 : 0
        brightSamples = bright ? brightSamples + 1 : 0
        if darkSamples >= 2 { on = true }
        if brightSamples >= 5 { on = false }
        return on
    }
}
