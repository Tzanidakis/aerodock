import AppKit
import SwiftUI

@MainActor
private final class LockCardState: ObservableObject {
    @Published var music = LockMusicSession()
}

private struct LockScreenCard: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var state: LockCardState
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if state.music.visible {
                    HStack(spacing: 16) {
                        AlbumCover(image: model.artwork?.image, accent: model.artwork?.accent ?? .mint, size: 76)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text(model.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 10) {
                                action("backward.end.fill", "Previous song") { model.runMusic("previous track") }
                                action(model.playing ? "pause.fill" : "play.fill", model.playing ? "Pause music" : "Resume music") { model.runMusic("playpause") }
                                action("forward.end.fill", "Next song") { model.runMusic("next track") }
                                action("stop.fill", "Stop music") {
                                    model.runMusic("pause")
                                    state.music.stop()
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if model.focus.active && !model.focus.finished {
                    HStack(spacing: 14) {
                        Image(systemName: "timer").font(.system(size: 24)).foregroundStyle(.mint).frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.focus.running ? "Focus" : "Focus paused").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(timerText).font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                        }
                        Spacer()
                        action(model.focus.running ? "pause.fill" : "play.fill", model.focus.running ? "Pause focus" : "Resume focus") {
                            if model.focus.running { model.focus.pause(now: Date()) } else { model.focus.start(now: Date()) }
                        }
                        action("stop.fill", "Stop and reset focus") { model.focus.stop() }
                    }
                }
                if model.recorder.recording {
                    HStack(spacing: 14) {
                        Image(systemName: "mic.fill").font(.system(size: 24)).foregroundStyle(.red).frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.recorder.paused ? "Recording paused" : "Recording").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(model.recorder.time).font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                        }
                        Spacer()
                        action(model.recorder.paused ? "play.fill" : "pause.fill", model.recorder.paused ? "Resume recording" : "Pause recording", model.recorder.togglePause)
                        action("stop.fill", "Finish and save recording", model.recorder.stop)
                    }
                }
                if model.presentation.running { Label("Presenting", systemImage: "text.alignleft").font(.system(size: 13, weight: .medium)) }
            }.padding(22)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
    private func action(_ icon: String, _ label: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 36)
        }.buttonStyle(DockRoundButtonStyle()).help(label).accessibilityLabel(label)
    }
    private var timerText: String {
        let seconds = Int(ceil(model.focus.remaining))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private final class LockCardHostingView: NSHostingView<LockScreenCard> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class LockedActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LockScreenDock {
    private let panel: NSPanel
    private let state = LockCardState()
    private let space = LockScreenSpace()
    private var lastPresentation = Date.distantPast
    init(model: IslandModel) {
        panel = LockedActivityPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 142), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = LockCardHostingView(rootView: LockScreenCard(model: model, state: state))
    }
    func update(locked: Bool, model: IslandModel) {
        let updated = state.music.updated(locked: locked, playing: model.playing)
        if updated != state.music { state.music = updated }
        let focus = model.focus.active && !model.focus.finished
        guard LockActivity.shouldShow(locked: locked, music: state.music.visible, focus: focus, recording: model.recorder.recording, presentation: model.presentation.running),
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            panel.orderOut(nil); space.conceal(); lastPresentation = .distantPast; return
        }
        let rows = [state.music.visible, focus, model.recorder.recording, model.presentation.running].filter { $0 }.count
        let contentHeight = 44 + (state.music.visible ? 108 : 0) + (focus ? 62 : 0) + (model.recorder.recording ? 62 : 0) + (model.presentation.running ? 24 : 0) + max(0, rows - 1) * 18
        let width = min(480, screen.frame.width - 48)
        let height = min(CGFloat(contentHeight), screen.frame.height * 0.45)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.midY - height / 2, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // Locking and display wake rebuild the visible Spaces even while isVisible stays true.
        if Date().timeIntervalSince(lastPresentation) >= 0.5 {
            lastPresentation = Date()
            if space.present(panel) { panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
    }
}
