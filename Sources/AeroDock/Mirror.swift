import AppKit
import AVFoundation
import SwiftUI

final class MirrorCapture: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var message = "Opening camera…"
    private let queue = DispatchQueue(label: "AeroDock.mirror")
    private var requested = false
    @Published var isDark = false
    private var lastSample = CMTime.zero
    private let ambientLight = AmbientLightReader()
    private var lightState = MirrorLightState()
    func start() {
        requested = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.requested else { return }
                    if granted { self.configure() } else { self.message = "Camera access denied" }
                }
            }
        default: message = "Allow camera in System Settings"
        }
    }
    private func configure() {
        queue.async { [self] in
            if session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    DispatchQueue.main.async { self.message = "Camera unavailable" }; return
                }
                session.beginConfiguration()
                session.sessionPreset = .medium
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: queue)
                }
                session.commitConfiguration()
            }
            session.startRunning()
            DispatchQueue.main.async { self.message = "" }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTimeGetSeconds(time - lastSample) >= 1,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastSample = time
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var total = 0, count = 0
        // Sample the central face area only, once a second. Frames are never saved.
        for y in stride(from: height / 4, to: height * 3 / 4, by: 16) {
            for x in stride(from: width / 4, to: width * 3 / 4, by: 16) {
                total += Int(pixels[y * row + x]); count += 1
            }
        }
        guard count > 0 else { return }
        let light = lightState.update(lux: ambientLight.readLux(), imageBrightness: Double(total) / Double(count))
        DispatchQueue.main.async { if self.isDark != light { self.isDark = light } }

    }
    func stop() {
        requested = false
        queue.async { [self] in session.stopRunning() }
    }
}

private final class MirrorPreview: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateMirroring() {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
    override func layout() { super.layout(); preview.frame = bounds; updateMirroring() }
}

private struct MirrorSurface: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> MirrorPreview {
        let view = MirrorPreview(frame: .zero)
        view.preview.session = session
        view.updateMirroring()
        return view
    }
    func updateNSView(_ view: MirrorPreview, context: Context) {
        view.updateMirroring()
    }
}

struct MirrorView: View {
    @StateObject private var capture = MirrorCapture()
    @State private var lightOverride: Bool?
    private var lightOn: Bool { lightOverride ?? capture.isDark }
    var body: some View {
        HStack(spacing: 12) {
        ZStack {
            Color.black
            MirrorSurface(session: capture.session)
                .id(capture.message.isEmpty)
            if !capture.message.isEmpty {
                Text(capture.message).font(.system(size: 10)).multilineTextAlignment(.center).padding(12)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
                .padding(.vertical, 25)
        .frame(maxWidth: .infinity)
        .background(lightOn ? Color.white : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: lightOn ? .white.opacity(0.5) : .clear, radius: 16)
        VStack(spacing: 14) {
        Button {
            lightOverride = !lightOn
        } label: {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(lightOn ? Color.white : .gray)
        }.buttonStyle(.plain).help("Toggle mirror light").accessibilityLabel("Mirror light")
        Button("Auto") { lightOverride = nil }.font(.system(size: 10, weight: .semibold)).buttonStyle(.plain).foregroundStyle(lightOverride == nil ? .mint : .gray)
        }
        }
        .accessibilityLabel("Live camera mirror")
        .onAppear { capture.start() }
        .onDisappear { capture.stop() }
    }
}
