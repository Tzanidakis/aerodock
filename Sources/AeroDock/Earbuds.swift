import AppKit
import SwiftUI

struct EarbudDevice: Equatable, Identifiable {
    let id: String
    let name: String
    let left: Int?
    let right: Int?
    let main: Int?
    let batteryCase: Int?
    var level: Int? { [left, right].compactMap { $0 }.min() ?? main }
    var icon: String { name.lowercased().contains("airpods") ? "airpodspro" : "earbuds" }

    static func parse(_ data: Data) throws -> [EarbudDevice] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let controllers = json?["SPBluetoothDataType"] as? [[String: Any]] ?? []
        return controllers.flatMap { controller -> [EarbudDevice] in
            let connected = controller["device_connected"] as? [[String: [String: Any]]] ?? []
            return connected.flatMap { entry in
                entry.compactMap { name, info -> EarbudDevice? in
                    let type = (info["device_minorType"] as? String ?? "").lowercased()
                    guard type.contains("headphone") || type.contains("headset") || name.lowercased().contains("airpods") else { return nil }
                    func battery(_ key: String) -> Int? {
                        guard let raw = info[key] as? String,
                              let value = Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), (0...100).contains(value) else { return nil }
                        return value
                    }
                    return EarbudDevice(id: info["device_address"] as? String ?? name, name: name,
                        left: battery("device_batteryLevelLeft"), right: battery("device_batteryLevelRight"),
                        main: battery("device_batteryLevelMain"), batteryCase: battery("device_batteryLevelCase"))
                }
            }
        }.sorted { $0.id < $1.id }
    }
}

@MainActor
final class EarbudMonitor {
    var onUpdate: (([EarbudDevice]) -> Void)?
    private var timer: Timer?
    private var refreshing = false
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let devices = await Task.detached(priority: .utility) { () -> [EarbudDevice]? in
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "4"]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { return nil }
                    return try EarbudDevice.parse(data)
                } catch { return nil }
            }.value
            refreshing = false
            if let devices { onUpdate?(devices) }
        }
    }
}

struct BatteryRing: View {
    let level: Int?
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 3)
            if let level {
                Circle().trim(from: 0, to: Double(level) / 100)
                    .stroke(level <= 20 ? Color.orange : .mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(level.map { "\($0)" } ?? "—").font(.system(size: 10, weight: .semibold, design: .rounded))
        }.frame(width: 32, height: 32)
        .accessibilityLabel(level.map { "Battery \($0) percent" } ?? "Battery unavailable")
    }
}

struct EarbudConnectionView: View {
    let device: EarbudDevice
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.icon).font(.system(size: 30)).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("Connected").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if device.left != nil || device.right != nil {
                gauge("L", device.left)
                gauge("R", device.right)
            } else { gauge("Battery", device.main) }
            if let batteryCase = device.batteryCase { gauge("Case", batteryCase) }
        }.padding(18).frame(height: 88)
    }
    private func gauge(_ label: String, _ level: Int?) -> some View {
        VStack(spacing: 4) {
            BatteryRing(level: level)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
