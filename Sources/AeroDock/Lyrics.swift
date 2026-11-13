import Foundation

struct LyricsRecord: Decodable {
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
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
    func reset() { task?.cancel(); task = nil; key = "" }
    func load(title: String, artist: String, duration: Double, completion: @escaping (String?) -> Void) {
        let next = "\(title)|\(artist)|\(Int(duration))"
        guard next != key else { return }
        task?.cancel(); key = next; completion(nil)
        guard !title.isEmpty, !artist.isEmpty, duration > 0, duration <= 3600, Date() >= retryAfter else { return }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 10
        request.setValue("AeroDock/0.7.3 (https://github.com/Tzanidakis/aerodock)", forHTTPHeaderField: "User-Agent")
        task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, key == next, let http = response as? HTTPURLResponse else { return }
                if http.statusCode == 429 {
                    retryAfter = Date().addingTimeInterval(max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                    return
                }
                guard http.statusCode == 200, data.count <= 1_000_000 else { return }
                completion(try JSONDecoder().decode(LyricsRecord.self, from: data).text)
            } catch { /* Missing lyrics and network errors leave the section hidden. */ }
        }
    }
}
