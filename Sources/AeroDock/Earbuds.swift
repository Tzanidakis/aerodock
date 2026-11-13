import AppKit
import SwiftUI
import IOBluetooth

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
final class EarbudMonitor: NSObject {
    var onUpdate: (([EarbudDevice]) -> Void)?
    private var timer: Timer?
    private var refreshing = false
    private var refreshPending = false
    private var revision = 0
    private var devices: [String: EarbudDevice] = [:]
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var lastBatteryRefresh = Date.distantPast
    private func identifier(_ device: IOBluetoothDevice) -> String {
        (device.addressString ?? "").replacingOccurrences(of: "-", with: ":").uppercased()
    }
    private func isHeadphone(_ device: IOBluetoothDevice) -> Bool {
        (device.name ?? "").lowercased().contains("airpods") ||
        (device.deviceClassMajor == kBluetoothDeviceClassMajorAudio &&
         [kBluetoothDeviceClassMinorAudioHeadset, kBluetoothDeviceClassMinorAudioHandsFree, kBluetoothDeviceClassMinorAudioHeadphones].contains(Int(device.deviceClassMinor)))
    }
    private func publish() { onUpdate?(devices.values.sorted { $0.id < $1.id }) }
    func start() {
        guard timer == nil else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        reconcile()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reconcile()
                if Date().timeIntervalSince(self.lastBatteryRefresh) >= 30 { self.refresh() }
            }
        }
    }
    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard isHeadphone(device) else { return }
        add(device)
    }
    private func add(_ device: IOBluetoothDevice) {
        let id = identifier(device)
        guard !id.isEmpty, devices[id] == nil else { return }
        revision += 1
        devices[id] = EarbudDevice(id: id, name: device.name ?? "Earbuds", left: nil, right: nil, main: nil, batteryCase: nil)
        disconnectNotifications[id] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        publish() // Show connection immediately; battery metadata follows asynchronously.
        refresh()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.refresh()
        }
    }
    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        remove(identifier(device))
    }
    private func remove(_ id: String) {
        guard devices.removeValue(forKey: id) != nil else { return }
        revision += 1
        disconnectNotifications.removeValue(forKey: id)?.unregister()
        publish()
    }
    private func reconcile() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        for device in paired where isHeadphone(device) {
            if device.isConnected() { add(device) } else { remove(identifier(device)) }
        }
    }
    private func refresh() {
        guard !refreshing else { refreshPending = true; return }
        refreshing = true
        lastBatteryRefresh = Date()
        let requestRevision = revision
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
            if let devices, requestRevision == revision {
                for device in devices {
                    let id = device.id.replacingOccurrences(of: "-", with: ":").uppercased()
                    // Battery snapshots never resurrect a device removed by a live event.
                    if self.devices[id] != nil { self.devices[id] = device }
                }
                publish()
            }
            if refreshPending { refreshPending = false; refresh() }
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
