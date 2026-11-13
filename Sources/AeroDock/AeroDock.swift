import AppKit
import SwiftUI
import EventKit

@main
struct AeroDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("AeroDock", systemImage: "rectangle.topthird.inset.filled") {
            Button("Show AeroDock") { delegate.show() }
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
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        show()
    }
    func show() { position(); panel.orderFrontRegardless() }
    @objc func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let size = NSSize(width: model.expanded ? 390 : 230, height: model.expanded ? 330 : 42)
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 6
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true, animate: true)
    }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var tab = 0
    @Published var title = "Your music, a little closer."
    @Published var artist = "Connect the Spotify desktop app"
    @Published var playing = false
    @Published var musicConnected = false
    @Published var message: String?
    @Published var events: [EKEvent] = []
    @Published var calendarConnected = false
    @Published var calendarMessage = "Your next plans, at a glance."
    var resize: (() -> Void)?
    private let eventStore = EKEventStore()
    private let musicQueue = DispatchQueue(label: "AeroDock.Spotify")
    private var refreshing = false
    func toggle() { expanded.toggle(); resize?() }
    func connectMusic() { musicConnected = true; refreshMusic() }
    func runSpotify(_ command: String) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            message = "Open Spotify, then connect again."
            title = "Spotify is not running"
            artist = "Use the Spotify desktop app"
            playing = false
            return
        }
        guard !refreshing else { return }
        refreshing = true
        musicQueue.async {
            var error: NSDictionary?
            let source = "tell application id \"com.spotify.client\"\n\(command)\nreturn {name of current track, artist of current track, player state as string}\nend tell"
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let values = (1...3).map { result?.atIndex($0)?.stringValue ?? "" }
            let failed = error != nil
            DispatchQueue.main.async {
                self.refreshing = false
                if failed {
                    self.message = "Allow Spotify control in System Settings → Privacy & Security → Automation, and play a track."
                    self.musicConnected = false
                } else {
                    self.title = values[0].isEmpty ? "Nothing playing" : values[0]
                    self.artist = values[1]
                    self.playing = values[2] == "playing"
                    self.message = nil
                }
            }
        }
    }
    func refreshMusic() { if musicConnected { runSpotify("") } }
    func connectCalendar() {
        Task {
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
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private let mint = Color(red: 0.65, green: 0.96, blue: 0.79)
    var body: some View {
        VStack(spacing: 0) {
            Button(action: model.toggle) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform").foregroundStyle(mint)
                    Text("AeroDock").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: model.expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                }.padding(.horizontal, 20).frame(height: 42).contentShape(Rectangle())
            }.buttonStyle(.plain).help(model.expanded ? "Collapse AeroDock" : "Expand AeroDock")
            if model.expanded {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        tabButton("Music", icon: "music.note", index: 0)
                        tabButton("Calendar", icon: "calendar", index: 1)
                        Spacer()
                        Text("YOUR LITTLE ISLAND").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(.gray)
                    }
                    if model.tab == 0 { music } else { calendar }
                    Spacer(minLength: 0)
                    HStack {
                        Circle().fill(mint).frame(width: 5, height: 5)
                        Text("A little less switching.").font(.system(size: 10)).foregroundStyle(.gray)
                        Spacer()
                        Text("AERODOCK 0.1").font(.system(size: 8, weight: .medium)).foregroundStyle(.gray)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.065, blue: 0.075))
        .clipShape(RoundedRectangle(cornerRadius: model.expanded ? 26 : 21))
        .overlay(RoundedRectangle(cornerRadius: model.expanded ? 26 : 21).stroke(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onReceive(timer) { _ in if model.expanded { model.refreshMusic(); if model.tab == 1 { model.refreshCalendar() } } }
        .onExitCommand { if model.expanded { model.toggle() } }
    }
    func tabButton(_ text: String, icon: String, index: Int) -> some View {
        Button { model.tab = index; if index == 1 { model.refreshCalendar() } } label: {
            Label(text, systemImage: icon).font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                .background(model.tab == index ? Color.white.opacity(0.12) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
    var music: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [mint.opacity(0.4), .teal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(mint)
                }.frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text("SPOTIFY").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(mint)
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
                Button("Connect Spotify", action: model.connectMusic).buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
            }
        }.padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
    func control(_ icon: String, label: String, command: String, prominent: Bool = false) -> some View {
        Button { model.runSpotify(command) } label: {
            Image(systemName: icon).font(.system(size: prominent ? 19 : 14)).frame(width: prominent ? 44 : 24, height: 44)
                .foregroundStyle(prominent ? .black : .white)
                .background(prominent ? mint : .clear, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
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
            if !model.calendarConnected { Button("Connect Calendar", action: model.connectCalendar).buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black) }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
}
