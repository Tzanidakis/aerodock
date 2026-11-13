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
        print("8 behavior and artwork tests passed")
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
        state.update(now: 0.1, inHotspot: false, inPanel: false, interacting: false)
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
