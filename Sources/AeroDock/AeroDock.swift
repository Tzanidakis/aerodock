import AppKit
import SwiftUI
import EventKit

@main
struct AeroDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("AeroDock", systemImage: "rectangle.topthird.inset.filled") {
            Button("Show AeroDock") { delegate.show() }
            Button("Hide AeroDock until I show it") { delegate.setMode(.hidden) }
            Button("Auto-hide · reveal near camera") { delegate.setMode(.automatic) }
            Button("Keep AeroDock visible") { delegate.setMode(.pinned) }
            Divider()
            Button("Quit AeroDock") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: IslandPanel!
    let model = IslandModel()
    private var visibility = VisibilityState()
    private var monitor: Timer?
    private var lastRefresh = Date.distantPast
    private var activeScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: IslandView(model: model))
        model.resize = { [weak self] in self?.position() }
        model.changeMode = { [weak self] in self?.setMode($0) }
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let saved = UserDefaults.standard.string(forKey: "visibilityMode") ?? "automatic"
        setMode(VisibilityState.Mode(rawValue: saved) ?? .automatic)
        if visibility.mode != .hidden { show() }
        monitor = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(monitor!, forMode: .common)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }
    func setMode(_ mode: VisibilityState.Mode) {
        visibility.setMode(mode)
        model.visibilityMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "visibilityMode")
        applyVisibility()
    }
    func show() {
        visibility.reveal(now: Date.timeIntervalSinceReferenceDate)
        model.visibilityMode = visibility.mode
        UserDefaults.standard.set(visibility.mode.rawValue, forKey: "visibilityMode")
        applyVisibility()
    }
    private func applyVisibility() {
        if visibility.visible {
            position(); panel.orderFrontRegardless(); model.refreshMusic()
        } else {
            model.expanded = false
            panel.orderOut(nil)
        }
    }
    private func tick() {
        model.focus.tick(now: Date())
        guard let screen = activeScreen else { return }
        let mouse = NSEvent.mouseLocation
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        let hot = NSRect(x: screen.frame.midX - 120, y: top - 10, width: 240, height: screen.frame.maxY - top + 10)
        // Include the small gap from the camera to the island so crossing it never hides controls.
        let overPanel = panel.isVisible && panel.frame.insetBy(dx: -8, dy: -10).contains(mouse)
        let old = visibility.visible
        visibility.update(now: Date.timeIntervalSinceReferenceDate, inHotspot: hot.contains(mouse), inPanel: overPanel,
                          interacting: model.interacting || (overPanel && NSEvent.pressedMouseButtons != 0))
        if old != visibility.visible { applyVisibility() }
        if visibility.visible && Date().timeIntervalSince(lastRefresh) >= 3 {
            lastRefresh = Date(); model.refreshMusic()
            if model.expanded && model.tab == 1 { model.refreshCalendar() }
        }
    }
    @objc func position() {
        guard let screen = activeScreen else { return }
        let size = NSSize(width: model.expanded ? 410 : 360, height: model.expanded ? 400 : 52)
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 4
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
    }

}

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var tab = 0
    @Published var visibilityMode: VisibilityState.Mode = .automatic
    @Published var focus = FocusClock()
    @Published var player = MusicPlayer(rawValue: UserDefaults.standard.string(forKey: "musicPlayer") ?? "Spotify") ?? .spotify
    @Published var title = "Your music, a little closer."
    @Published var artist = "Choose a music app above"
    @Published var playing = false
    @Published var musicConnected = false
    @Published var message: String?
    @Published var events: [EKEvent] = []
    @Published var calendarConnected = false
    @Published var calendarMessage = "Your next plans, at a glance."
    @Published var launchMessage: String?
    var interacting = false
    var resize: (() -> Void)?
    var changeMode: ((VisibilityState.Mode) -> Void)?
    private let eventStore = EKEventStore()
    private let musicQueue = DispatchQueue(label: "AeroDock.Music")
    private var refreshing = false
    private var generation = 0
    init() {
        musicConnected = UserDefaults.standard.bool(forKey: "connected.\(player.rawValue)")
    }
    func toggle() { expanded.toggle(); resize?() }
    func selectPlayer(_ value: MusicPlayer) {
        generation += 1; player = value; playing = false; message = nil
        title = "Your music, a little closer."; artist = value.rawValue
        UserDefaults.standard.set(value.rawValue, forKey: "musicPlayer")
        musicConnected = UserDefaults.standard.bool(forKey: "connected.\(value.rawValue)")
        refreshMusic()
    }
    func connectMusic() {
        musicConnected = true
        UserDefaults.standard.set(true, forKey: "connected.\(player.rawValue)")
        runMusic("")
    }
    func disconnectMusic() {
        generation += 1; musicConnected = false; playing = false; message = nil
        title = "Music disconnected"; artist = "Connect when you are ready"
        UserDefaults.standard.set(false, forKey: "connected.\(player.rawValue)")
    }
    func runMusic(_ command: String) {
        guard musicConnected else { return }
        let selected = player
        guard NSRunningApplication.runningApplications(withBundleIdentifier: selected.bundleID).first != nil else {
            message = "Open \(selected.rawValue), then play a track."
            title = "\(selected.rawValue) is not running"; artist = "Open the desktop app"; playing = false
            return
        }
        // Polls may be skipped, but never discard a user's playback command.
        if command.isEmpty && refreshing { return }
        refreshing = true
        let requestGeneration = generation
        musicQueue.async {
            var error: NSDictionary?
            let source = """
            with timeout of 5 seconds
                tell application id "\(selected.bundleID)"
                    \(command)
                    set playbackState to player state as string
                    try
                        return {name of current track, artist of current track, playbackState}
                    on error
                        return {"Nothing playing", "Choose a track in \(selected.rawValue)", playbackState}
                    end try
                end tell
            end timeout
            """
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let values = (1...3).map { result?.atIndex($0)?.stringValue ?? "" }
            let failed = error != nil
            DispatchQueue.main.async {
                self.refreshing = false
                guard self.generation == requestGeneration else { return }
                if failed {
                    self.message = "Could not control \(selected.rawValue). Check Privacy & Security → Automation, then reconnect."
                    self.musicConnected = false; self.playing = false
                    UserDefaults.standard.set(false, forKey: "connected.\(selected.rawValue)")
                } else {
                    self.title = values[0].isEmpty ? "Nothing playing" : values[0]
                    self.artist = values[1]; self.playing = values[2] == "playing"; self.message = nil
                }
            }
        }
    }
    func refreshMusic() { if musicConnected { runMusic("") } }
    func openApp(_ id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            launchMessage = "This app is not installed on your Mac."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            Task { @MainActor in self.launchMessage = error == nil ? nil : "Could not open this app." }
        }
    }
    func connectCalendar() {
        interacting = true
        Task {
            defer { interacting = false }
            do {
                calendarConnected = try await eventStore.requestFullAccessToEvents()
                calendarMessage = calendarConnected ? "No upcoming events in the next 7 days." : "Calendar access is off. Enable AeroDock in System Settings → Privacy & Security → Calendars."
                refreshCalendar()
            } catch { calendarMessage = "Could not connect to Calendar. Please try again." }
        }
    }
    func refreshCalendar() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; calendarConnected = false; return
        }
        calendarConnected = true
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        events = Array(eventStore.events(matching: eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)).filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }.prefix(3))
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    private let mint = Color(red: 0.65, green: 0.96, blue: 0.79)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: model.toggle) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").foregroundStyle(mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.musicConnected ? model.title : "AeroDock").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(model.focus.running ? "Focus · \(focusTime)" : (model.musicConnected ? model.player.rawValue : "Hover. Play. Get on with your day.")).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(model.expanded ? "Collapse AeroDock" : "Expand AeroDock")
                if model.musicConnected {
                    control("backward.end.fill", label: "Previous song", command: "previous track")
                    control(model.playing ? "pause.fill" : "play.fill", label: model.playing ? "Pause" : "Play", command: "playpause")
                    control("forward.end.fill", label: "Next song", command: "next track")
                }
                Button { model.changeMode?(.hidden) } label: {
                    Image(systemName: "eye.slash").font(.system(size: 12)).foregroundStyle(.gray)
                }.buttonStyle(.plain).help("Hide until you choose Show AeroDock in the menu bar").accessibilityLabel("Hide AeroDock")
            }.padding(.horizontal, 16).frame(height: 52)
            if model.expanded {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        tabButton("Music", icon: "music.note", index: 0)
                        tabButton("Calendar", icon: "calendar", index: 1)
                        tabButton("Focus", icon: "timer", index: 2)
                        tabButton("Apps", icon: "square.grid.2x2", index: 3)
                    }
                    if model.tab == 0 { music }
                    else if model.tab == 1 { calendar }
                    else if model.tab == 2 { focus }
                    else { apps }
                    Spacer(minLength: 0)
                    HStack {
                        Circle().fill(mint).frame(width: 5, height: 5)
                        Text(model.visibilityMode == .pinned ? "Pinned on screen" : "Tucks away when you leave").font(.system(size: 10)).foregroundStyle(.gray)
                        Spacer()
                        Button(model.visibilityMode == .pinned ? "Unpin" : "Pin") {
                            model.changeMode?(model.visibilityMode == .pinned ? .automatic : .pinned)
                        }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.065, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: model.expanded ? 26 : 21))
        .overlay(RoundedRectangle(cornerRadius: model.expanded ? 26 : 21).stroke(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onExitCommand { if model.expanded { model.toggle() } }
    }
    func tabButton(_ text: String, icon: String, index: Int) -> some View {
        Button { model.tab = index; if index == 1 { model.refreshCalendar() } } label: {
            Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(model.tab == index ? Color.white.opacity(0.12) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
    var music: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Music app", selection: Binding(get: { model.player }, set: model.selectPlayer)) {
                ForEach(MusicPlayer.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [mint.opacity(0.4), .teal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(mint)
                }.frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.player.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(mint)
                    Text(model.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text(model.artist).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                }
            }
            if model.musicConnected && model.message == nil {
                HStack(spacing: 27) {
                    Spacer()
                    control("backward.end.fill", label: "Previous song", command: "previous track")
                    control(model.playing ? "pause.fill" : "play.fill", label: model.playing ? "Pause" : "Play", command: "playpause", prominent: true)
                    control("forward.end.fill", label: "Next song", command: "next track")
                    control("stop.fill", label: "Stop playback", command: "pause")
                    Spacer()
                }
            } else {
                Text(model.message ?? "Connect once to control playback from your island.").font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                Button("Connect \(model.player.rawValue)", action: model.connectMusic).buttonStyle(MintButtonStyle())
            }
            HStack {
                Button("Open \(model.player.rawValue)") { model.openApp(model.player.bundleID) }
                Spacer()
                if model.musicConnected { Button("Disconnect", action: model.disconnectMusic) }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint)
        }.padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
    func control(_ icon: String, label: String, command: String, prominent: Bool = false) -> some View {
        Button { model.runMusic(command) } label: {
            Image(systemName: icon).font(.system(size: prominent ? 19 : 14)).frame(width: prominent ? 44 : 24, height: 44)
                .foregroundStyle(prominent ? .black : .white)
                .background(prominent ? mint : .clear, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
    var focusTime: String {
        let seconds = Int(ceil(model.focus.remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var focus: some View {
        VStack(spacing: 14) {
            Text(model.focus.finished ? "Nice work. Take a breath." : "A little space to concentrate.").font(.system(size: 12)).foregroundStyle(.gray)
            Text(focusTime).font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(mint)
            HStack {
                ForEach([5, 25, 50], id: \.self) { minutes in
                    Button("\(minutes) min") { model.focus.reset(minutes: minutes) }.disabled(model.focus.running)
                }
            }.buttonStyle(.bordered)
            HStack {
                Button(model.focus.running ? "Pause" : "Start focus") {
                    if model.focus.running { model.focus.pause(now: Date()) } else { model.focus.start(now: Date()) }
                }.buttonStyle(MintButtonStyle())
                Button("Reset") { model.focus.reset(minutes: 25) }.buttonStyle(.bordered)
            }
            Text("Keeps time while AeroDock is hidden. No notification sounds.").font(.system(size: 10)).foregroundStyle(.gray)
        }.frame(maxWidth: .infinity).padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
    var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ONE CLICK AWAY").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(mint)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(QuickApp.all) { app in
                    Button { model.openApp(app.id) } label: {
                        Label(app.name, systemImage: app.symbol).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) == nil)
                }
            }
            Text(model.launchMessage ?? "Open your apps without searching the Dock.").font(.system(size: 10)).foregroundStyle(.gray)
        }.padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
    var calendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("UP NEXT").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(mint)
                Spacer()
                Button("Open Calendar") { NSWorkspace.shared.open(URL(string: "ical://")!) }.font(.system(size: 10)).buttonStyle(.plain)
            }
            if model.events.isEmpty {
                Text(model.calendarMessage).font(.system(size: 13)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
            ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(mint).frame(width: 3, height: 35)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title ?? "Untitled event").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(event.isAllDay ? "All day · \(event.startDate.formatted(date: .abbreviated, time: .omitted))" : event.startDate.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.gray)
                    }
                    Spacer()
                }
            }
            if !model.calendarConnected { Button("Connect Calendar", action: model.connectCalendar).buttonStyle(MintButtonStyle()) }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
}


enum MusicPlayer: String, CaseIterable {
    case spotify = "Spotify", appleMusic = "Apple Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}
struct QuickApp: Identifiable {
    let id: String
    let name: String
    let symbol: String
    static let all = [
        QuickApp(id: "com.apple.Notes", name: "Notes", symbol: "note.text"),
        QuickApp(id: "com.apple.reminders", name: "Reminders", symbol: "checklist"),
        QuickApp(id: "com.apple.iCal", name: "Calendar", symbol: "calendar"),
        QuickApp(id: "com.apple.mail", name: "Mail", symbol: "envelope"),
        QuickApp(id: "com.apple.shortcuts", name: "Shortcuts", symbol: "square.stack.3d.up"),
        QuickApp(id: "com.apple.calculator", name: "Calculator", symbol: "plus.forwardslash.minus")
    ]
}

struct MintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(.black)
            .background(Color(red: 0.65, green: 0.96, blue: 0.79).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
