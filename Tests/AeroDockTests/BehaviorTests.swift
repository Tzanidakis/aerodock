import Foundation
import AppKit
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Values differ", file: file, line: line) }

@main
struct BehaviorTests {
    static func main() {
        let tests = BehaviorTests()
        tests.testFocusStopRestoresSelectedDuration()
        tests.testCustomFocusDuration()
        tests.testTimedLyricsFollowPlayback()
        tests.testDisplayHotspots()
        tests.testTraySnapshotsAndCancelledDrags()
        tests.testLockMusicPauseAndResume()
        tests.testInteractiveHUDAndLockActivity()
        tests.testLevelChanges()
        tests.testMirrorLightHysteresis()
        tests.testLyricsAvailability()
        tests.testEarbudBatteryParsing()
        tests.testHoverMustDwellAndLeavingHides()
        tests.testCrossingGapAndReturningCancelsHide()
        tests.testHiddenNeverRevealsUntilExplicitlyShown()
        tests.testPinnedIgnoresPointerAndAutoHideResets()
        tests.testBriefPassOverCameraDoesNotReveal()
        tests.testFocusUsesElapsedTimeAcrossSleepAndPause()
        tests.testArtworkRejectsInvalidBytes()
        tests.testArtworkDownsamplesAndExtractsColor()
        tests.testPresentationEmptyAndChunking()
        tests.testPresentationPauseAndManualNavigation()
        tests.testPresentationEndAndReplay()
        tests.testPresentationDoesNotSkipAfterSleep()
        tests.testDeletedRecordingsDisappear()
        tests.testActivityTucksAwayAndReveals()
        print("25 behavior, artwork, presentation and recording tests passed")
    }
    func testFocusStopRestoresSelectedDuration() {
        var clock = FocusClock()
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        clock.reset(minutes: 5)
        clock.start(now: now)
        clock.pause(now: now.addingTimeInterval(30))
        XCTAssertTrue(clock.active)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(clock.remaining, 270)
        clock.start(now: now.addingTimeInterval(100))
        XCTAssertEqual(clock.remaining, 270)
        clock.stop()
        XCTAssertFalse(clock.active)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(clock.remaining, 300)
        clock.start(now: now)
        clock.tick(now: now.addingTimeInterval(301))
        XCTAssertTrue(clock.finished)
        clock.start(now: now.addingTimeInterval(400))
        XCTAssertEqual(clock.remaining, 300)
    }
    func testCustomFocusDuration() {
        var clock = FocusClock()
        clock.reset(minutes: 90)
        XCTAssertEqual(clock.remaining, 5400)
        clock.start(now: Date(timeIntervalSinceReferenceDate: 0))
        clock.pause(now: Date(timeIntervalSinceReferenceDate: 60))
        XCTAssertEqual(clock.remaining, 5340)
        clock.stop()
        XCTAssertEqual(clock.remaining, 5400)
        clock.reset(minutes: 0)
        XCTAssertEqual(clock.remaining, 60)
        clock.reset(minutes: 9999)
        XCTAssertEqual(clock.remaining, 1439 * 60)
    }
    func testTimedLyricsFollowPlayback() {
        let lines = TimedLyric.parse("[ar:Example]\n[00:10.50]First\n[00:20.000][01:00.25]Repeated\n[00:30.00]\n[00:99]Invalid")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(TimedLyric.current(in: lines, at: 0) == nil)
        XCTAssertEqual(TimedLyric.current(in: lines, at: 10.5), 0)
        XCTAssertEqual(TimedLyric.current(in: lines, at: 25), 1)
        XCTAssertEqual(TimedLyric.current(in: lines, at: 35), 2)
        XCTAssertEqual(TimedLyric.current(in: lines, at: 61), 3)
        XCTAssertEqual(TimedLyric.current(in: lines, at: 11), 0)
        XCTAssertEqual(lines[3].time, 60.25)
        XCTAssertTrue(TimedLyric.parse(nil).isEmpty)
    }
    func testDisplayHotspots() {
        let external = CGRect(x: 1920, y: -200, width: 2560, height: 1440)
        let hot = DisplayHotspot.frame(screen: external, notchWidth: 64, notchHeight: 0)
        XCTAssertTrue(hot.contains(CGPoint(x: external.midX, y: external.maxY - 1)))
        XCTAssertFalse(hot.contains(CGPoint(x: external.minX + 20, y: external.maxY - 1)))
        XCTAssertEqual(hot.midX, external.midX)
        let notched = DisplayHotspot.frame(screen: CGRect(x: -1512, y: 0, width: 1512, height: 982), notchWidth: 180, notchHeight: 38)
        XCTAssertEqual(notched.width, 196)
        XCTAssertEqual(notched.height, 52)
    }
    func testTraySnapshotsAndCancelledDrags() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("example.txt")
        try! Data("original".utf8).write(to: original)
        let storage = try! TrayStorage(root: root.appendingPathComponent("tray"))
        let first = try! storage.copy(original)
        let second = try! storage.copy(original)
        XCTAssertTrue(first != second)
        XCTAssertEqual(first.lastPathComponent, "example.txt")
        try! Data("changed".utf8).write(to: original)
        XCTAssertEqual(try! String(contentsOf: first, encoding: .utf8), "original")
        XCTAssertEqual(try! String(contentsOf: original, encoding: .utf8), "changed")
        try! FileManager.default.removeItem(at: original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(TrayDragResult.shouldRemove([]))
        XCTAssertTrue(TrayDragResult.shouldRemove(.copy))
        XCTAssertFalse(TrayDragResult.shouldRemove(.delete))
    }
    func testLockMusicPauseAndResume() {
        var state = LockMusicSession()
        state = state.updated(locked: true, playing: false)
        XCTAssertFalse(state.visible)
        state = state.updated(locked: true, playing: true)
        XCTAssertTrue(state.visible)
        state = state.updated(locked: true, playing: false)
        XCTAssertTrue(state.visible)
        state.stop()
        state = state.updated(locked: true, playing: false)
        XCTAssertFalse(state.visible)
        state = state.updated(locked: true, playing: true)
        XCTAssertTrue(state.visible)
        state = state.updated(locked: false, playing: true)
        XCTAssertFalse(state.visible)
    }
    func testInteractiveHUDAndLockActivity() {
        XCTAssertEqual(LevelHUDLayout.level(at: 0), 1)
        XCTAssertEqual(LevelHUDLayout.level(at: 63), 0.5)
        XCTAssertEqual(LevelHUDLayout.level(at: 200), 0)
        XCTAssertEqual(LevelHUDLayout.inset(brightness: false, bothVisibleOnSameScreen: false), 4)
        XCTAssertEqual(LevelHUDLayout.inset(brightness: true, bothVisibleOnSameScreen: false), 4)
        XCTAssertEqual(LevelHUDLayout.inset(brightness: false, bothVisibleOnSameScreen: true), 72)
        XCTAssertFalse(LockActivity.shouldShow(locked: true, music: false, focus: false, recording: false, presentation: false))
        XCTAssertFalse(LockActivity.shouldShow(locked: false, music: true, focus: true, recording: true, presentation: true))
        for index in 0..<4 {
            XCTAssertTrue(LockActivity.shouldShow(locked: true, music: index == 0, focus: index == 1, recording: index == 2, presentation: index == 3))
        }
    }
    func testLevelChanges() {
        var tracker = LevelChangeTracker()
        XCTAssertTrue(tracker.update(key: "volume", value: 0.5) == nil)
        XCTAssertTrue(tracker.update(key: "volume", value: 0.501) == nil)
        XCTAssertEqual(tracker.update(key: "volume", value: 0.6), 60)
        XCTAssertEqual(tracker.update(key: "volume", value: 0), 0)
        XCTAssertTrue(tracker.update(key: "brightness", value: 0.4) == nil)
        XCTAssertEqual(tracker.update(key: "brightness", value: 0.7), 70)
        XCTAssertTrue(tracker.update(key: "volume", value: nil) == nil)
        XCTAssertTrue(tracker.update(key: "volume", value: 0.8) == nil)
        XCTAssertEqual(tracker.update(key: "volume", value: 2), 100)
        XCTAssertTrue(tracker.update(key: "volume", value: .nan) == nil)
    }
    func testMirrorLightHysteresis() {
        var state = MirrorLightState()
        XCTAssertFalse(state.update(lux: 10, imageBrightness: 200))
        XCTAssertTrue(state.update(lux: 10, imageBrightness: 200))
        XCTAssertTrue(state.update(lux: 45, imageBrightness: 200))
        for _ in 0..<4 { XCTAssertTrue(state.update(lux: 100, imageBrightness: 20)) }
        XCTAssertFalse(state.update(lux: 100, imageBrightness: 20))
        XCTAssertFalse(state.update(lux: nil, imageBrightness: 20))
        XCTAssertTrue(state.update(lux: nil, imageBrightness: 20))
        XCTAssertTrue(state.update(lux: nil, imageBrightness: 200))
    }
    func testLyricsAvailability() {
        let match = LyricsRecord(trackName: "Belladonna", artistName: "UFO", duration: 265, instrumental: false, plainLyrics: "Example", syncedLyrics: nil)
        XCTAssertEqual(LyricsRecord.bestMatch([match], title: "Belladonna - 2007 Remaster", artist: "UFO", duration: 262)?.text, "Example")
        XCTAssertTrue(LyricsRecord.bestMatch([match], title: "Belladonna - Live", artist: "UFO", duration: 262) == nil)
        XCTAssertTrue(LyricsRecord.bestMatch([match], title: "Belladonna", artist: "Different artist", duration: 262) == nil)
        XCTAssertTrue(LyricsRecord.bestMatch([match], title: "Belladonna", artist: "UFO", duration: 300) == nil)
        XCTAssertTrue(LyricsRecord(instrumental: true, plainLyrics: "ignored", syncedLyrics: nil).text == nil)
        XCTAssertTrue(LyricsRecord(instrumental: false, plainLyrics: "  ", syncedLyrics: nil).text == nil)
        XCTAssertEqual(LyricsRecord(instrumental: false, plainLyrics: "Example line", syncedLyrics: nil).text, "Example line")
        XCTAssertEqual(LyricsRecord(instrumental: false, plainLyrics: nil, syncedLyrics: "[ar:Example]\n[00:01.00]Example line\n[00:02.50]Another line").text, "Example line\nAnother line")
    }
    func testEarbudBatteryParsing() {
        let data = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_address":"test","device_minorType":"Headphones","device_batteryLevelLeft":"0%","device_batteryLevelRight":"87%","device_batteryLevelCase":"101%"}},
          {"Mouse":{"device_minorType":"Mouse","device_batteryLevelMain":"80%"}},
          {"Headset":{"device_minorType":"Headset","device_batteryLevelMain":"unknown"}}
        ],"device_not_connected":[{"AirPods":{"device_batteryLevelMain":"99%"}}]}]}
        """.utf8)
        let devices = try! EarbudDevice.parse(data)
        XCTAssertEqual(devices.count, 2)
        let airpods = devices.first { $0.id == "test" }!
        XCTAssertEqual(airpods.level, 0)
        XCTAssertEqual(airpods.right, 87)
        XCTAssertTrue(airpods.batteryCase == nil)
        XCTAssertTrue(devices.first { $0.name == "Headset" }!.level == nil)
        XCTAssertTrue(try! EarbudDevice.parse(Data("{}".utf8)).isEmpty)
    }
    func testActivityTucksAwayAndReveals() {
        var state = VisibilityState()
        state.reveal(now: 0)
        state.update(now: 4, inHotspot: false, inPanel: false, interacting: false, active: true)
        state.update(now: 8.9, inHotspot: false, inPanel: false, interacting: false, active: true)
        XCTAssertTrue(state.visible)
        state.update(now: 9, inHotspot: false, inPanel: false, interacting: false, active: true)
        XCTAssertFalse(state.visible)
        state.update(now: 10, inHotspot: true, inPanel: false, interacting: false, active: true)
        state.update(now: 10.1, inHotspot: true, inPanel: false, interacting: false, active: true)
        XCTAssertTrue(state.visible)
        state.update(now: 20, inHotspot: false, inPanel: true, interacting: false, active: true)
        XCTAssertTrue(state.visible)
        state.setMode(.hidden)
        state.update(now: 30, inHotspot: true, inPanel: false, interacting: false, active: true)
        XCTAssertFalse(state.visible)
    }
    func testDeletedRecordingsDisappear() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("Voice-001.m4a")
        let recent = folder.appendingPathComponent("Voice-002.m4a")
        let active = folder.appendingPathComponent("Voice-003.m4a")
        for file in [old, recent, active] { try! Data([1]).write(to: file) }
        try! FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.m4a"), withIntermediateDirectories: true)
        XCTAssertEqual(RecordingFiles.list(in: folder, excluding: active), [recent, old].map { $0.resolvingSymlinksInPath() })
        try! FileManager.default.removeItem(at: recent)
        XCTAssertEqual(RecordingFiles.list(in: folder, excluding: active), [old.resolvingSymlinksInPath()])
        try! FileManager.default.moveItem(at: old, to: folder.appendingPathComponent("moved.txt"))
        XCTAssertEqual(RecordingFiles.list(in: folder, excluding: active), [])
    }
    func testPresentationEmptyAndChunking() {
        var p = Presentation()
        p.load("  \n  ")
        p.play(now: Date())
        XCTAssertFalse(p.running)
        p.load((1...25).map(String.init).joined(separator: " "))
        XCTAssertEqual(p.cards.count, 3)
        XCTAssertEqual(p.cards[0].split(separator: " ").count, 12)
        XCTAssertEqual(p.cards.last, "25")
    }
    func testPresentationPauseAndManualNavigation() {
        var p = Presentation(); p.load("Hello world\nNext thought")
        let now = Date()
        p.play(now: now); p.tick(now: now.addingTimeInterval(0.2))
        XCTAssertTrue(p.progress > 0)
        p.pause(); let progress = p.progress
        p.tick(now: now.addingTimeInterval(10)); XCTAssertEqual(p.progress, progress)
        p.move(1); XCTAssertEqual(p.current, "Next thought")
        XCTAssertEqual(p.progress, 0)
        p.move(20); XCTAssertEqual(p.index, 1)
        p.move(-20); XCTAssertEqual(p.index, 0)
    }
    func testPresentationEndAndReplay() {
        var p = Presentation(); p.load("Hello")
        let now = Date(); p.play(now: now)
        for n in 1...8 { p.tick(now: now.addingTimeInterval(Double(n) * 0.25)) }
        XCTAssertTrue(p.finished); XCTAssertFalse(p.running)
        p.play(now: now.addingTimeInterval(3))
        XCTAssertTrue(p.running); XCTAssertEqual(p.progress, 0)
    }
    func testPresentationDoesNotSkipAfterSleep() {
        var p = Presentation(); p.load("One two three four five six\nNext passage")
        let now = Date(); p.play(now: now)
        p.tick(now: now.addingTimeInterval(3600))
        XCTAssertEqual(p.index, 0); XCTAssertTrue(p.progress < 0.2)
    }
    func testArtworkRejectsInvalidBytes() {
        XCTAssertTrue(CoverArt.decode(Data("not an image".utf8)) == nil)
        XCTAssertTrue(CoverArt.decode(Data(repeating: 0, count: 10_000_001)) == nil)
    }
    func testArtworkDownsamplesAndExtractsColor() {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pixels = bitmap.bitmapData!
        for y in 0..<512 { for x in 0..<512 {
            let i = y * bitmap.bytesPerRow + x * 4
            pixels[i] = 255; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 255
        } }
        let data = bitmap.representation(using: .png, properties: [:])!
        let cover = CoverArt.decode(data)!
        XCTAssertTrue(cover.image.size.width <= 256)
        let accent = NSColor(cover.accent).usingColorSpace(.deviceRGB)!
        XCTAssertTrue(accent.redComponent > accent.greenComponent)
        XCTAssertTrue(accent.redComponent > 0.7)
    }
    func testHoverMustDwellAndLeavingHides() {
        var state = VisibilityState()
        state.update(now: 0, inHotspot: true, inPanel: false, interacting: false)
        XCTAssertFalse(state.visible)
        state.update(now: 0.2, inHotspot: true, inPanel: false, interacting: false)
        XCTAssertTrue(state.visible)
        state.update(now: 1, inHotspot: false, inPanel: false, interacting: false)
        state.update(now: 1.7, inHotspot: false, inPanel: false, interacting: false)
        XCTAssertTrue(state.visible)
        state.update(now: 1.8, inHotspot: false, inPanel: false, interacting: false)
        XCTAssertFalse(state.visible)
    }
    func testCrossingGapAndReturningCancelsHide() {
        var state = VisibilityState()
        state.reveal(now: 0)
        state.update(now: 4, inHotspot: false, inPanel: false, interacting: false)
        state.update(now: 4.5, inHotspot: false, inPanel: true, interacting: false)
        state.update(now: 6, inHotspot: false, inPanel: true, interacting: false)
        XCTAssertTrue(state.visible)
        state.update(now: 7, inHotspot: false, inPanel: false, interacting: true)
        XCTAssertTrue(state.visible)
    }
    func testHiddenNeverRevealsUntilExplicitlyShown() {
        var state = VisibilityState()
        state.setMode(.hidden)
        state.update(now: 0, inHotspot: true, inPanel: true, interacting: false)
        state.update(now: 10, inHotspot: true, inPanel: true, interacting: false)
        XCTAssertFalse(state.visible)
        state.reveal(now: 11)
        XCTAssertEqual(state.mode, .automatic)
        XCTAssertTrue(state.visible)
        state.update(now: 12, inHotspot: false, inPanel: false, interacting: false)
        XCTAssertTrue(state.visible)
    }
    func testPinnedIgnoresPointerAndAutoHideResets() {
        var state = VisibilityState()
        state.setMode(.pinned)
        state.update(now: 100, inHotspot: false, inPanel: false, interacting: false)
        XCTAssertTrue(state.visible)
        state.setMode(.automatic)
        XCTAssertFalse(state.visible)
        // The eye button returns even a pinned island to hover-reveal mode.
        state.update(now: 101, inHotspot: true, inPanel: false, interacting: false, active: true)
        state.update(now: 101.1, inHotspot: true, inPanel: false, interacting: false, active: true)
        XCTAssertTrue(state.visible)
        state.setMode(.automatic)
        XCTAssertFalse(state.visible)
    }
    func testBriefPassOverCameraDoesNotReveal() {
        var state = VisibilityState()
        state.update(now: 0, inHotspot: true, inPanel: false, interacting: false)
        state.update(now: 0.04, inHotspot: false, inPanel: false, interacting: false)
        state.update(now: 1, inHotspot: true, inPanel: false, interacting: false)
        XCTAssertFalse(state.visible)
    }
    func testFocusUsesElapsedTimeAcrossSleepAndPause() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var clock = FocusClock()
        clock.reset(minutes: 5)
        clock.start(now: start)
        clock.pause(now: start.addingTimeInterval(40))
        XCTAssertEqual(clock.remaining, 260)
        clock.tick(now: start.addingTimeInterval(1000))
        XCTAssertEqual(clock.remaining, 260)
        clock.start(now: start.addingTimeInterval(1000))
        clock.tick(now: start.addingTimeInterval(1300))
        XCTAssertEqual(clock.remaining, 0)
        XCTAssertTrue(clock.finished)
        XCTAssertFalse(clock.running)
        clock.reset(minutes: 50)
        XCTAssertFalse(clock.finished)
        XCTAssertEqual(clock.remaining, 3000)
    }
}
