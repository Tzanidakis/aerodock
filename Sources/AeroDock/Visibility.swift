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
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?
    var finished = false
    var running: Bool { deadline != nil }
    mutating func start(now: Date) {
        if remaining <= 0 { remaining = 25 * 60 }
        finished = false; deadline = now.addingTimeInterval(remaining)
    }
    mutating func tick(now: Date) {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if remaining == 0 { self.deadline = nil; finished = true }
    }
    mutating func pause(now: Date) { tick(now: now); deadline = nil }
    mutating func reset(minutes: Int) { deadline = nil; remaining = Double(minutes * 60); finished = false }
}
