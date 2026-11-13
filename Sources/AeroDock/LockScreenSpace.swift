import AppKit
import Darwin
import OSLog

/// Optional WindowServer integration; only the non-keyboard activity card is admitted here.
/// API declarations and space levels: https://github.com/Lakr233/SkyLightWindow
@MainActor
final class LockScreenSpace {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Level = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias Add = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private let library: UnsafeMutableRawPointer?
    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var show: Spaces?
    private var hide: Spaces?
    private var add: Add?
    private var visible = false
    private let logger = Logger(subsystem: "com.tzanidakis.aerodock", category: "LockScreen")
    init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let library,
              let connectionSymbol = dlsym(library, "SLSMainConnectionID"),
              let createSymbol = dlsym(library, "SLSSpaceCreate"),
              let levelSymbol = dlsym(library, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(library, "SLSShowSpaces"),
              let hideSymbol = dlsym(library, "SLSHideSpaces"),
              let addSymbol = dlsym(library, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            logger.error("Lock-screen space API unavailable")
            return
        }
        connection = unsafeBitCast(connectionSymbol, to: Connection.self)()
        let created = unsafeBitCast(createSymbol, to: Create.self)(connection, 1, 0)
        guard created > 0 else { logger.error("Lock-screen space creation failed"); return }
        let status = unsafeBitCast(levelSymbol, to: Level.self)(connection, created, 400)
        guard status == 0 else { logger.error("Lock-screen space level failed: \(status)"); return }
        space = created
        show = unsafeBitCast(showSymbol, to: Spaces.self)
        hide = unsafeBitCast(hideSymbol, to: Spaces.self)
        add = unsafeBitCast(addSymbol, to: Add.self)
        logger.notice("Lock-screen space initialized")
    }
    func present(_ window: NSWindow) -> Bool {
        guard space != 0, let show, let add else { return false }
        let shown = show(connection, [space] as CFArray)
        let adopted = add(connection, space, [window.windowNumber] as CFArray, 7)
        let success = shown == 0 && adopted == 0
        if success && !visible { logger.notice("Lock-screen card admitted to visible space") }
        if !success { logger.error("Lock-screen presentation failed: show=\(shown), add=\(adopted)") }
        visible = success
        return success
    }
    func conceal() {
        guard space != 0, visible else { return }
        _ = hide?(connection, [space] as CFArray)
        visible = false
    }
    // Keep framework loaded for the app lifetime; WindowServer reclaims the space on exit.
}
