import AppKit
import SwiftUI
import QuickLookThumbnailing

struct TrayFile: Identifiable {
    let id: UUID
    let url: URL
    var preview: NSImage
}

enum TrayDragResult {
    static func shouldRemove(_ operation: NSDragOperation) -> Bool { !operation.intersection([.copy, .move, .link, .generic]).isEmpty }
}

struct TrayStorage {
    let folder: URL
    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AeroDock-FileTray", isDirectory: true)) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Expired copies are removed on a later launch, allowing receiving apps time to read dropped URLs.
        for old in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let created = try? old.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(created) > 86400 { try? FileManager.default.removeItem(at: old) }
        }
        folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    func copy(_ source: URL) throws -> URL {
        guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let destination = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = destination.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: file)
        return file
    }
}

@MainActor
final class FileTray: NSObject, ObservableObject, NSSharingServiceDelegate {
    @Published var files: [TrayFile] = []
    @Published var message = "Files stay here for this session. Originals are unchanged."
    @Published private(set) var copying = false
    @Published private(set) var sharing = false
    var dragging = false
    var busy: Bool { copying || sharing || dragging }
    private var storage: TrayStorage?
    private let queue = DispatchQueue(label: "AeroDock.FileTray", qos: .userInitiated)
    private var service: NSSharingService?
    private var sharedIDs: [UUID] = []
    override init() {
        super.init()
        do { storage = try TrayStorage() } catch { message = "Could not create temporary storage." }
    }
    func receive(_ urls: [URL], airDrop: Bool) {
        guard !copying, !sharing, let storage, !urls.isEmpty else { return }
        copying = true; message = "Copying files…"
        queue.async {
            var copied: [URL] = []; var failed = 0
            for url in urls {
                do { copied.append(try storage.copy(url)) } catch { failed += 1 }
            }
            DispatchQueue.main.async {
                self.copying = false
                let items = copied.map { TrayFile(id: UUID(), url: $0, preview: NSWorkspace.shared.icon(forFile: $0.path)) }
                self.files.append(contentsOf: items)
                for item in items { self.loadPreview(item) }
                self.message = failed == 0 ? "Drag a file out to use it. Cancelled drags stay here." : "Some files could not be copied. Successfully copied files are in the tray."
                if airDrop { self.send(items) }
            }
        }
    }
    private func loadPreview(_ item: TrayFile) {
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 160, height: 120), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] result, _ in
            guard let result else { return }
            DispatchQueue.main.async {
                guard let self, let index = self.files.firstIndex(where: { $0.id == item.id }) else { return }
                self.files[index].preview = result.nsImage
            }
        }
    }
    func remove(_ id: UUID) { files.removeAll { $0.id == id } }
    func send(_ items: [TrayFile]) {
        guard !sharing, !items.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items.map(\.url)) else {
            message = "AirDrop is unavailable. Your files remain in the tray."; return
        }
        self.service = service; service.delegate = self
        sharedIDs = items.map(\.id); sharing = true
        message = "Choose an AirDrop recipient. Files stay here if sharing is cancelled."
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items.map(\.url))
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        for id in sharedIDs { remove(id) }
        sharing = false; sharedIDs = []; service = nil; message = "Sent with AirDrop."
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        sharing = false; sharedIDs = []; service = nil; message = "AirDrop did not finish. Your files are still in the tray."
    }
}

private struct FileTile: View {
    let item: TrayFile
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: item.preview).resizable().scaledToFit().frame(width: 90, height: 62)
            Text(item.url.lastPathComponent).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
        }.padding(8).frame(width: 116, height: 105).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}

private final class FileDragView: NSView, NSDraggingSource {
    var item: TrayFile!
    weak var tray: FileTray?
    var consume = true
    private var host: NSHostingView<FileTile>?
    func update(_ file: TrayFile) {
        item = file
        if let host { host.rootView = FileTile(item: file) }
        else { let view = NSHostingView(rootView: FileTile(item: file)); host = view; addSubview(view) }
    }
    override func layout() { super.layout(); host?.frame = bounds }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        guard let item, FileManager.default.fileExists(atPath: item.url.path) else { return }
        consume = true; tray?.dragging = true
        let dragging = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        dragging.setDraggingFrame(bounds, contents: item.preview)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        tray?.dragging = false
        if consume && TrayDragResult.shouldRemove(operation) { tray?.remove(item.id) }
    }
}

private struct FileDragTile: NSViewRepresentable {
    let item: TrayFile
    let tray: FileTray
    func makeNSView(context: Context) -> FileDragView { let view = FileDragView(); view.tray = tray; view.update(item); return view }
    func updateNSView(_ view: FileDragView, context: Context) { view.update(item) }
}

private struct DropLabel: View {
    let airDrop: Bool
    let hovering: Bool
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: airDrop ? "antenna.radiowaves.left.and.right" : "tray.and.arrow.down").font(.system(size: 23, weight: .light))
            Text(airDrop ? "Drop to AirDrop" : "Drop files here").font(.system(size: 12, weight: .semibold))
            Text(airDrop ? "Choose a recipient" : "Temporary file tray").font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? Color.mint : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

private final class FileDropView: NSView {
    var airDrop = false
    weak var tray: FileTray?
    private var host: NSHostingView<DropLabel>?
    func configure() {
        registerForDraggedTypes([.fileURL])
        if host == nil { let view = NSHostingView(rootView: DropLabel(airDrop: airDrop, hovering: false)); host = view; addSubview(view) }
    }
    override func layout() { super.layout(); host?.frame = bounds }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let tray, !tray.copying, !tray.sharing else { return false }
        if sender.draggingSource is FileDragView && !airDrop { return false }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let allowed = accepts(sender)
        host?.rootView = DropLabel(airDrop: airDrop, hovering: allowed)
        return allowed ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { host?.rootView = DropLabel(airDrop: airDrop, hovering: false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { host?.rootView = DropLabel(airDrop: airDrop, hovering: false) }
        guard accepts(sender), let tray else { return false }
        if let source = sender.draggingSource as? FileDragView, let item = source.item {
            source.consume = false
            tray.send([item]); return true
        }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        tray.receive(urls, airDrop: airDrop); return true
    }
}

private struct FileDropZone: NSViewRepresentable {
    let tray: FileTray
    let airDrop: Bool
    func makeNSView(context: Context) -> FileDropView { let view = FileDropView(); view.tray = tray; view.airDrop = airDrop; view.configure(); return view }
    func updateNSView(_ view: FileDropView, context: Context) {}
}

struct FileTrayView: View {
    @ObservedObject var tray: FileTray
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FileDropZone(tray: tray, airDrop: false)
                FileDropZone(tray: tray, airDrop: true)
            }.frame(height: 104)
            if tray.copying { ProgressView().controlSize(.small) }
            if !tray.files.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116))], spacing: 10) {
                    ForEach(tray.files) { item in
                        FileDragTile(item: item, tray: tray).frame(width: 116, height: 105)
                            .overlay(alignment: .topTrailing) {
                                Button { tray.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).help("Remove from tray").accessibilityLabel("Remove \(item.url.lastPathComponent) from tray")
                            }
                    }
                }
            }
            Text(tray.message).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
