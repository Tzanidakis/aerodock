import AppKit
import AVFoundation
import SwiftUI

final class MirrorCapture: ObservableObject {
    let session = AVCaptureSession()
    @Published var message = "Opening camera…"
    private let queue = DispatchQueue(label: "AeroDock.mirror")
    private var requested = false
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
                session.commitConfiguration()
            }
            session.startRunning()
            DispatchQueue.main.async { self.message = "" }
        }
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
    override func layout() { super.layout(); preview.frame = bounds }
}

private struct MirrorSurface: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> MirrorPreview {
        let view = MirrorPreview(frame: .zero)
        view.preview.session = session
        return view
    }
    func updateNSView(_ view: MirrorPreview, context: Context) {
        if let connection = view.preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

struct MirrorView: View {
    @StateObject private var capture = MirrorCapture()
    var body: some View {
        ZStack {
            Color.black
            MirrorSurface(session: capture.session)
            if !capture.message.isEmpty {
                Text(capture.message).font(.system(size: 10)).multilineTextAlignment(.center).padding(12)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(Circle().stroke(.mint.opacity(0.65), lineWidth: 2))
        .accessibilityLabel("Live camera mirror")
        .onAppear { capture.start() }
        .onDisappear { capture.stop() }
    }
}
