import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var recording = false
    @Published private(set) var requesting = false
    @Published private(set) var finishing = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Double = 0
    @Published private(set) var files: [URL] = []
    @Published var message = "Record your microphone. Audio stays on this Mac."
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var recordingFailed = false
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AeroDock/Recordings", isDirectory: true)
    }
    var time: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    override init() { super.init(); reload() }
    func start() {
        guard !recording, !requesting, !finishing else { return }
        requesting = true
        recordingFailed = false
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            requesting = false
            guard allowed else {
                message = "Microphone access is off. Enable AeroDock in System Settings → Privacy & Security → Microphone."
                return
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted)).replacingOccurrences(of: ":", with: "-")
                let url = folder.appendingPathComponent("Voice-\(stamp)-\(UUID().uuidString.prefix(6)).m4a")
                let audio = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ])
                audio.delegate = self; audio.isMeteringEnabled = true
                guard audio.prepareToRecord(), audio.record() else { throw CocoaError(.fileWriteUnknown) }
                recorder = audio; currentURL = url; elapsed = 0; level = 0; recording = true
                message = "Recording microphone…"
            } catch { message = "Could not start recording. Check your microphone and available disk space." }
        }
    }
    func tick() {
        guard recording, let recorder else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        level = max(0, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
    }
    func stop() {
        guard recording else { return }
        tick(); recording = false; finishing = true; level = 0
        message = "Saving recording…"
        recorder?.stop()
    }
    func stopForQuit() { recorder?.stop() }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.recording = false; self.finishing = false; self.level = 0; self.recorder = nil
            self.message = flag && !self.recordingFailed ? "Saved on this Mac. Play it or export a copy below." : "Recording stopped unexpectedly. Check the saved file before using it."
            self.currentURL = nil; self.reload()
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.recordingFailed = true
            self.recorder?.stop(); self.recording = false; self.finishing = false; self.level = 0
            self.recorder = nil; self.currentURL = nil
            self.message = "Recording failed. Check your audio input and disk space."
            self.reload()
        }
    }
    func reload() {
        files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "m4a" && $0 != currentURL }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func showFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch { message = "Could not open the recordings folder." }
    }
    func export(_ file: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = file.lastPathComponent
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if destination.standardizedFileURL == file.standardizedFileURL { return }
                let data = try Data(contentsOf: file)
                try data.write(to: destination, options: .atomic)
                self.message = "Exported a copy of your recording."
            } catch { self.message = "Could not export this recording. Choose another location." }
        }
    }
}

struct RecorderView: View {
    @ObservedObject var recorder: VoiceRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: recorder.recording ? "mic.fill" : "mic").foregroundStyle(recorder.recording ? .red : .mint)
                Text(recorder.recording ? "RECORDING" : "VOICE RECORDER").font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
                Text(recorder.time).font(.system(size: 23, weight: .light, design: .monospaced))
            }
            ProgressView(value: recorder.level).tint(.red).accessibilityLabel("Microphone level")
            Text(recorder.message).font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(recorder.recording ? "Stop & save" : (recorder.requesting ? "Waiting for microphone…" : "Start recording")) {
                    if recorder.recording { recorder.stop() } else { recorder.start() }
                }.buttonStyle(MintButtonStyle()).disabled(recorder.requesting || recorder.finishing)
                Spacer()
                Button("Files", action: recorder.showFolder).buttonStyle(.plain)
            }
            if !recorder.files.isEmpty {
                Divider()
                Text("RECENT RECORDINGS").font(.system(size: 9, weight: .bold)).foregroundStyle(.gray)
                ForEach(Array(recorder.files.prefix(3)), id: \.self) { file in
                    HStack {
                        Text(file.deletingPathExtension().lastPathComponent).lineLimit(1).font(.system(size: 10))
                        Spacer()
                        Button { NSWorkspace.shared.open(file) } label: { Image(systemName: "play.circle") }.help("Play recording in your audio app")
                        Button { recorder.export(file) } label: { Image(systemName: "square.and.arrow.up") }.help("Export recording")
                    }.buttonStyle(.plain)
                }
            }
        }.padding(15).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
    }
}
