import AppKit
import SwiftUI
import ImageIO

struct CoverArt {
    let image: NSImage
    let accent: Color
    static func decode(_ data: Data) -> CoverArt? {
        guard data.count <= 10_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        // Sample a tiny bitmap; favor saturated colors rather than black borders or white text.
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let rgb: (Double, Double, Double) = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return (0.65, 0.96, 0.79)
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            var buckets: [Int: (weight: Double, r: Double, g: Double, b: Double)] = [:]
            for i in stride(from: 0, to: buffer.count, by: 4) {
                guard buffer[i + 3] > 200 else { continue }
                let r = Double(buffer[i]) / 255, g = Double(buffer[i + 1]) / 255, b = Double(buffer[i + 2]) / 255
                let high = max(r, g, b), low = min(r, g, b)
                guard high > 0.12 else { continue }
                let weight = 0.1 + (high - low) * 3
                let key = (Int(r * 5) * 36) + (Int(g * 5) * 6) + Int(b * 5)
                let old = buckets[key] ?? (0, 0, 0, 0)
                buckets[key] = (old.weight + weight, old.r + r * weight, old.g + g * weight, old.b + b * weight)
            }
            guard let best = buckets.values.max(by: { $0.weight < $1.weight }) else { return (0.65, 0.96, 0.79) }
            let color = NSColor(srgbRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
            let bright = NSColor(calibratedHue: color.hueComponent, saturation: min(0.8, color.saturationComponent), brightness: max(0.8, color.brightnessComponent), alpha: 1).usingColorSpace(.deviceRGB)!
            return (bright.redComponent, bright.greenComponent, bright.blueComponent)
        }
        return CoverArt(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), accent: Color(red: rgb.0, green: rgb.1, blue: rgb.2))
    }
}

@MainActor
final class ArtworkLoader {
    private var task: Task<Void, Never>?
    private var key: String?
    private var cache: [String: CoverArt] = [:]
    private var cacheOrder: [String] = []
    private var attempt: UUID?
    func reset() { task?.cancel(); task = nil; key = nil; attempt = nil }
    func load(key newKey: String, url: String?, bytes: Data?, deliver: @escaping (CoverArt?) -> Void) {
        guard newKey != key else { return }
        reset(); key = newKey
        let token = UUID(); attempt = token
        let cacheKey = url ?? newKey
        if let cached = cache[cacheKey] { deliver(cached); return }
        deliver(nil)
        task = Task {
            var result: CoverArt?
            if let bytes, !bytes.isEmpty { result = CoverArt.decode(bytes) }
            else if let url, let endpoint = URL(string: url), endpoint.scheme == "https" {
                do {
                    var request = URLRequest(url: endpoint, timeoutInterval: 12)
                    request.cachePolicy = .returnCacheDataElseLoad
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                          data.count <= 10_000_000 else { throw URLError(.badServerResponse) }
                    result = CoverArt.decode(data)
                } catch { /* Missing/offline artwork must never interrupt playback controls. */ }
            }
            guard !Task.isCancelled, attempt == token else { return }
            if let result {
                cache[cacheKey] = result
                cacheOrder.append(cacheKey)
                if cacheOrder.count > 24 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
            }
            deliver(result)
        }
    }
}

struct AlbumCover: View {
    let image: NSImage?
    let accent: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.4), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(accent) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
        .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityLabel(image == nil ? "No album artwork" : "Current song artwork")
    }
}

/// Decorative animation based on playback state, not microphone input or beat analysis.
struct PlaybackGlow: View {
    let accent: Color
    let playing: Bool
    let visible: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || !visible || reduceMotion)) { timeline in
            let t = playing && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            let pulse = 0.65 + 0.2 * sin(t * 2.2)
            let shape = RoundedRectangle(cornerRadius: cornerRadius).inset(by: 2)
            let gradient = AngularGradient(colors: [accent, .cyan.opacity(0.7), accent.opacity(0.2), accent, .white.opacity(0.65), accent], center: .center, angle: .degrees(t.truncatingRemainder(dividingBy: 8) * 45))
            ZStack {
                shape.stroke(gradient, lineWidth: 8).blur(radius: 7).opacity(playing ? pulse * 0.7 : 0)
                shape.stroke(gradient, lineWidth: 1.5).opacity(playing ? pulse : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PlaybackBars: View {
    let accent: Color
    let playing: Bool
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing || !visible || reduceMotion)) { timeline in
            let t = playing && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    Capsule().fill(accent).frame(width: 2, height: playing ? 4 + 10 * abs(sin(t * (2.4 + Double(index) * 0.35) + Double(index))) : 3)
                }
            }.frame(width: 14, height: 16)
        }.accessibilityLabel(playing ? "Playing" : "Paused")
    }
}
