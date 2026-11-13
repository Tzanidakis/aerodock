import Foundation

struct RecordingFiles {
    static func list(in folder: URL, excluding activeFile: URL? = nil) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? [])
            .filter {
                FileManager.default.fileExists(atPath: $0.path) &&
                $0.pathExtension.lowercased() == "m4a" && $0.resolvingSymlinksInPath() != activeFile?.resolvingSymlinksInPath() &&
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .map { $0.resolvingSymlinksInPath() }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
