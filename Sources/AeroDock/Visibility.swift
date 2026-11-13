import Foundation

/// Independent of the window so reveal delays and hide behavior can be tested.
struct VisibilityState {
    enum Mode: String, CaseIterable { case automatic, pinned, hidden }
    var mode: Mode = .automatic
    private(set) var visible = false
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?
    private var holdUntil: TimeInterval = 0
    mutating func setMode(_ mode: Mode) {
        self.mode = mode
        visible = mode == .pinned
        enteredAt = nil; leftAt = nil; holdUntil = 0
    }
    mutating func reveal(now: TimeInterval) {
        if mode == .hidden { mode = .automatic }
        visible = true; holdUntil = now + 3; leftAt = nil
    }
    mutating func update(now: TimeInterval, inHotspot: Bool, inPanel: Bool, interacting: Bool, active: Bool = false) {
        guard mode == .automatic else { visible = mode == .pinned; return }
        if visible {
            enteredAt = nil
            if inHotspot || inPanel || interacting || now < holdUntil { leftAt = nil }
            else {
                if leftAt == nil { leftAt = now }
                if now - (leftAt ?? now) >= (active ? 5 : 0.75) { visible = false; leftAt = nil }
            }
        } else if inHotspot {
            if enteredAt == nil { enteredAt = now }
            if now - (enteredAt ?? now) >= 0.08 { visible = true; leftAt = nil }
        } else { enteredAt = nil }
    }
}

struct FocusClock {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var active = false
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?
    var finished = false
    var running: Bool { deadline != nil }
    mutating func start(now: Date) {
        if remaining <= 0 { remaining = duration }
        active = true
        finished = false; deadline = now.addingTimeInterval(remaining)
    }
    mutating func tick(now: Date) {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if remaining == 0 { self.deadline = nil; finished = true }
    }
    mutating func pause(now: Date) { tick(now: now); deadline = nil }
    mutating func stop() { deadline = nil; remaining = duration; finished = false; active = false }
    mutating func reset(minutes: Int) { duration = Double(min(1439, max(1, minutes)) * 60); stop() }
}

struct LockActivity {
    static func shouldShow(locked: Bool, music: Bool, focus: Bool, recording: Bool, presentation: Bool) -> Bool {
        locked && (music || focus || recording || presentation)
    }
}

struct LockMusicSession: Equatable {
    private(set) var visible = false
    func updated(locked: Bool, playing: Bool) -> Self {
        var next = self
        if !locked { next.visible = false }
        else if playing { next.visible = true }
        return next
    }
    mutating func stop() { visible = false }
}
