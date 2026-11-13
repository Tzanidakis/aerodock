import Foundation
import AppKit
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true", file: file, line: line) }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Values differ", file: file, line: line) }

@main
struct BehaviorTests {
    static func main() {
        let tests = BehaviorTests()
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
        print("13 behavior, artwork, presentation and recording tests passed")
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
