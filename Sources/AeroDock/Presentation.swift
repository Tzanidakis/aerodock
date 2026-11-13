import Foundation

struct Presentation {
    var cards: [String] = []
    var index = 0
    var running = false
    var wordsPerMinute = 120.0
    var progress = 0.0
    private var lastTick: Date?
    var current: String { cards.indices.contains(index) ? cards[index] : "Paste your speech to get started." }
    var finished: Bool { !cards.isEmpty && index == cards.count - 1 && progress >= 1 }
    mutating func load(_ text: String) {
        // Small cards make the next thought readable at a glance near the camera.
        cards = text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
            let words = paragraph.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return stride(from: 0, to: words.count, by: 12).map { start in
                words[start..<min(start + 12, words.count)].joined(separator: " ")
            }
        }
        index = 0; progress = 0; running = false; lastTick = nil
    }
    mutating func play(now: Date) {
        guard !cards.isEmpty else { return }
        if finished { index = 0; progress = 0 }
        running = true; lastTick = now
    }
    mutating func pause() { running = false; lastTick = nil }
    mutating func move(_ offset: Int) {
        index = min(max(0, index + offset), max(0, cards.count - 1))
        progress = 0; lastTick = nil
    }
    mutating func tick(now: Date) {
        guard running, !cards.isEmpty else { return }
        defer { lastTick = now }
        guard let lastTick else { return }
        // After sleep/stalls, never jump past unread cards. Resume at the same passage.
        let delta = min(0.25, max(0, now.timeIntervalSince(lastTick)))
        let duration = max(1, Double(current.split(separator: " ").count) * 60 / max(40, wordsPerMinute))
        progress += delta / duration
        if progress >= 1 {
            if index + 1 < cards.count { index += 1; progress = 0 }
            else { progress = 1; pause() }
        }
    }
}
