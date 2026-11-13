import AppKit
import SwiftUI
import CoreAudio
import Darwin

struct LevelChangeTracker {
    private var last: [String: Int] = [:]
    mutating func update(key: String, value: Double?) -> Int? {
        guard let value, value.isFinite else { last.removeValue(forKey: key); return nil }
        let percent = Int((min(1, max(0, value)) * 100).rounded())
        let previous = last.updateValue(percent, forKey: key)
        return previous != nil && previous != percent ? percent : nil
    }
}

struct LevelHUDLayout {
    static func inset(brightness: Bool, bothVisibleOnSameScreen: Bool) -> CGFloat {
        !brightness && bothVisibleOnSameScreen ? 72 : 4
    }
    static func level(at y: Double) -> Double { min(1, max(0, 1 - y / 126)) }
}

final class SystemLevelReader {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    func brightness(display: UInt32) -> Double? {
        guard let displayServices, let symbol = dlsym(displayServices, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        guard unsafeBitCast(symbol, to: GetBrightness.self)(display, &value) == 0 else { return nil }
        return Double(value)
    }
    func setBrightness(_ value: Double, display: UInt32) -> Bool {
        typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
        guard let displayServices, let symbol = dlsym(displayServices, "DisplayServicesSetBrightness") else { return false }
        return unsafeBitCast(symbol, to: SetBrightness.self)(display, Float(min(1, max(0, value)))) == 0
    }
    private func write<T>(_ object: UInt32, selector: UInt32, element: UInt32 = 0, value: T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return false }
        var copy = value
        return withUnsafePointer(to: &copy) { AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0) == noErr }
    }
    func setVolume(_ value: Double) -> Bool {
        guard let output = volume() else { return false }
        let level = Float(min(1, max(0, value)))
        var success = write(output.device, selector: kAudioDevicePropertyVolumeScalar, value: level)
        if !success {
            let left = write(output.device, selector: kAudioDevicePropertyVolumeScalar, element: 1, value: level)
            let right = write(output.device, selector: kAudioDevicePropertyVolumeScalar, element: 2, value: level)
            success = left || right
        }
        if success && level > 0 { _ = write(output.device, selector: kAudioDevicePropertyMute, value: UInt32(0)) }
        return success
    }
    private func read<T>(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: UInt32 = 0, initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &result) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr ? pointer.pointee : nil
        }
    }
    func volume() -> (device: UInt32, level: Double)? {
        guard let device: UInt32 = read(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal, initial: UInt32(0)), device != 0 else { return nil }
        let mute: UInt32? = read(device, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, initial: UInt32(0))
        if mute == 1 { return (device, 0) }
        if let master: Float = read(device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, initial: Float(0)) { return (device, Double(master)) }
        let channels: [Float] = [1, 2].compactMap { read(device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: $0, initial: Float(0)) }
        guard !channels.isEmpty else { return nil }
        return (device, Double(channels.reduce(0, +) / Float(channels.count)))
    }
    deinit { if let displayServices { dlclose(displayServices) } }
}

@MainActor
private final class LevelHUDModel: ObservableObject {
    @Published var percent = 0
    var adjust: ((Double) -> Void)?
    var interaction: ((Bool) -> Void)?
    let brightness: Bool
    init(brightness: Bool) { self.brightness = brightness }
}

private struct LevelHUDView: View {
    @ObservedObject var model: LevelHUDModel
    @State private var hovering = false
    @State private var dragging = false
    var body: some View {
        VStack(spacing: 12) {
            Text("\(model.percent)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(.white).frame(height: 126 * Double(model.percent) / 100)
            }.frame(width: 10, height: 126).clipShape(Capsule())
                .frame(width: 44, height: 126).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    dragging = true; model.interaction?(true)
                    model.adjust?(LevelHUDLayout.level(at: event.location.y))
                }.onEnded { _ in dragging = false; model.interaction?(hovering) })
                .accessibilityAdjustableAction { direction in
                    model.adjust?(min(1, max(0, Double(model.percent) / 100 + (direction == .increment ? 0.05 : -0.05))))
                }
            Image(systemName: model.brightness ? "sun.max.fill" : model.percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .medium)).frame(height: 20)
        }.padding(.vertical, 17).frame(width: 60)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .onHover { inside in hovering = inside; model.interaction?(inside || dragging) }
            .environment(\.colorScheme, .dark)
            .accessibilityLabel("\(model.brightness ? "Brightness" : "Volume") \(model.percent) percent")
    }
}

@MainActor
private final class LevelHUD {
    private let model: LevelHUDModel
    private let panel: NSPanel
    private(set) var screen: NSScreen?
    var isVisible: Bool { panel.isVisible }
    var visibilityChanged: (() -> Void)?
    var adjust: ((Double) -> Void)?
    private var interacting = false
    private var dismissal: Task<Void, Never>?
    init(brightness: Bool) {
        model = LevelHUDModel(brightness: brightness)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 224), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LevelHUDView(model: model))
        model.adjust = { [weak self] value in self?.adjust?(value) }
        model.interaction = { [weak self] active in
            guard let self else { return }
            self.interacting = active
            if active { self.dismissal?.cancel() } else { self.scheduleDismissal() }
        }
    }
    func show(percent: Int, screen: NSScreen) {
        dismissal?.cancel()
        model.percent = percent
        self.screen = screen
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }, completionHandler: nil)
        panel.orderFrontRegardless()
        visibilityChanged?()
        scheduleDismissal()
    }
    func position(inset: CGFloat) {
        guard let screen else { return }
        let bounds = screen.frame
        panel.setFrameOrigin(NSPoint(x: bounds.maxX - inset - 60, y: bounds.midY - 112))
    }
    private func scheduleDismissal() {
        dismissal?.cancel()
        guard !interacting else { return }
        dismissal = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_400_000_000) } catch { return }
            guard let self else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    self.panel.animator().alphaValue = 0
                }, completionHandler: nil)
                do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
            }
            self.panel.orderOut(nil)
            self.visibilityChanged?()
        }
    }
}

@MainActor
final class SystemLevelMonitor {
    private let reader = SystemLevelReader()
    private var tracker = LevelChangeTracker()
    private let volumeHUD = LevelHUD(brightness: false)
    private let brightnessHUD = LevelHUD(brightness: true)
    private var timer: Timer?
    private var previousDevice: UInt32?
    func start() {
        guard timer == nil else { return }
        volumeHUD.visibilityChanged = { [weak self] in self?.layout() }
        brightnessHUD.visibilityChanged = { [weak self] in self?.layout() }
        volumeHUD.adjust = { [weak self] value in
            guard let self, self.reader.setVolume(value), let actual = self.reader.volume(), let screen = self.volumeHUD.screen else { return }
            self.volumeHUD.show(percent: Int((actual.level * 100).rounded()), screen: screen)
        }
        brightnessHUD.adjust = { [weak self] value in
            guard let self, let screen = self.brightnessHUD.screen,
                  let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
                  self.reader.setBrightness(value, display: display), let actual = self.reader.brightness(display: display) else { return }
            self.brightnessHUD.show(percent: Int((actual * 100).rounded()), screen: screen)
        }
        sample()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func layout() {
        let together = volumeHUD.isVisible && brightnessHUD.isVisible && volumeHUD.screen == brightnessHUD.screen
        volumeHUD.position(inset: LevelHUDLayout.inset(brightness: false, bothVisibleOnSameScreen: together))
        brightnessHUD.position(inset: LevelHUDLayout.inset(brightness: true, bothVisibleOnSameScreen: together))
    }
    private func sample() {
        let screens = NSScreen.screens
        if let volume = reader.volume() {
            if previousDevice != volume.device { _ = tracker.update(key: "volume", value: nil); previousDevice = volume.device }
            if let percent = tracker.update(key: "volume", value: volume.level),
               let screen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
                volumeHUD.show(percent: percent, screen: screen)
            }
        } else { _ = tracker.update(key: "volume", value: nil) }
        for screen in screens {
            guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { continue }
            if let percent = tracker.update(key: "brightness-\(display)", value: reader.brightness(display: display)) {
                brightnessHUD.show(percent: percent, screen: screen)
            }
        }
    }
}
