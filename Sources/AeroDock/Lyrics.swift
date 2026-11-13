import Foundation

struct LyricsRecord: Decodable {
    var trackName: String? = nil
    var artistName: String? = nil
    var duration: Double? = nil
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    static func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"(?i)\s*(?:[-–]\s*|[\[(])(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?[\])]?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func bestMatch(_ records: [LyricsRecord], title: String, artist: String, duration: Double) -> LyricsRecord? {
        records.filter {
            normalizedTitle($0.trackName ?? "") == normalizedTitle(title) &&
            ($0.artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
            abs(($0.duration ?? -100) - duration) <= 15 && $0.text != nil
        }.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
    }

    var text: String? {
        guard !instrumental else { return nil }
        let plain = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plain.isEmpty { return plain }
        let lines = (syncedLyrics ?? "").components(separatedBy: .newlines).compactMap { line -> String? in
            guard line.range(of: #"^\[\d+:\d+(?:\.\d+)?\]"#, options: .regularExpression) != nil else { return nil }
            return line.replacingOccurrences(of: #"\[\d+:\d+(?:\.\d+)?\]"#, with: "", options: .regularExpression)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.isEmpty ? nil : lines
    }
}

@MainActor
final class LyricsLoader {
    private var task: Task<Void, Never>?
    private var key = ""
    private var retryAfter = Date.distantPast
    private var nextAttempt = Date.distantFuture
    func reset() { task?.cancel(); task = nil; key = "" }
    func load(title: String, artist: String, duration: Double, completion: @escaping (String?) -> Void) {
        let next = "\(title)|\(artist)|\(Int(duration))"
        guard Date() >= retryAfter, next != key || Date() >= nextAttempt else { return }
        nextAttempt = .distantFuture
        task?.cancel(); key = next; completion(nil)
        guard !title.isEmpty, !artist.isEmpty, duration > 0, duration <= 3600, Date() >= retryAfter else { return }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 10
        request.setValue("AeroDock/0.7.4 (https://github.com/Tzanidakis/aerodock)", forHTTPHeaderField: "User-Agent")
        task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, key == next, let http = response as? HTTPURLResponse else { return }
                if http.statusCode == 429 {
                    retryAfter = Date().addingTimeInterval(max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                    nextAttempt = retryAfter
                    return
                }
                if http.statusCode == 200, data.count <= 1_000_000 {
                    let record = try JSONDecoder().decode(LyricsRecord.self, from: data)
                    if record.instrumental { return }
                    if let text = record.text { completion(text); return }
                } else if http.statusCode != 404 {
                    nextAttempt = Date().addingTimeInterval(60); return
                }
                // Exact signatures often miss remasters. Match title and artist, then the closest duration.
                try await Task.sleep(nanoseconds: 300_000_000)
                var search = URLComponents(string: "https://lrclib.net/api/search")!
                search.queryItems = [URLQueryItem(name: "track_name", value: LyricsRecord.normalizedTitle(title)), URLQueryItem(name: "artist_name", value: artist)]
                request.url = search.url
                let (matches, searchResponse) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, key == next, let searchHTTP = searchResponse as? HTTPURLResponse else { return }
                if searchHTTP.statusCode == 429 {
                    retryAfter = Date().addingTimeInterval(max(60, Double(searchHTTP.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                    nextAttempt = retryAfter
                    return
                }
                guard searchHTTP.statusCode == 200, matches.count <= 5_000_000 else {
                    nextAttempt = Date().addingTimeInterval(60); return
                }
                let records = try JSONDecoder().decode([LyricsRecord].self, from: matches)
                completion(LyricsRecord.bestMatch(records, title: title, artist: artist, duration: duration)?.text)
            } catch {
                if !Task.isCancelled, key == next { nextAttempt = Date().addingTimeInterval(60) }
            }
        }
    }
}
