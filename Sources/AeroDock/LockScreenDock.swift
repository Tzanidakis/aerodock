import AppKit
import SwiftUI

private struct LockScreenCard: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "waveform.path").font(.system(size: 26, weight: .light)).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 8) {
                Text("AeroDock").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if model.playing {
                    Text(model.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(model.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 16) {
                    if model.focus.running {
                        Label(timerText, systemImage: "timer").monospacedDigit()
                    }
                    if model.recorder.recording {
                        Label(model.recorder.paused ? "Recording paused" : model.recorder.time, systemImage: "mic.fill").foregroundStyle(.red).monospacedDigit()
                    }
                    if model.presentation.running { Label("Presenting", systemImage: "text.alignleft") }
                }.font(.system(size: 13, weight: .medium, design: .rounded))
            }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 420, height: 142)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
    private var timerText: String {
        let seconds = Int(ceil(model.focus.remaining))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private final class LockedActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LockScreenDock {
    private let panel: NSPanel
    private let space = LockScreenSpace()
    private var lastPresentation = Date.distantPast
    init(model: IslandModel) {
        panel = LockedActivityPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 142), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LockScreenCard(model: model))
    }
    func update(locked: Bool, model: IslandModel) {
        guard LockActivity.shouldShow(locked: locked, music: model.playing, focus: model.focus.running, recording: model.recorder.recording, presentation: model.presentation.running),
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            panel.orderOut(nil); space.conceal(); lastPresentation = .distantPast; return
        }
        let point = NSPoint(x: screen.frame.midX - 210, y: screen.frame.midY - 71)
        if panel.frame.origin != point { panel.setFrameOrigin(point) }
        // Locking and display wake rebuild the visible Spaces even while isVisible stays true.
        if Date().timeIntervalSince(lastPresentation) >= 0.5 {
            lastPresentation = Date()
            if space.present(panel) { panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
    }
}
