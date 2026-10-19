import Foundation

/// Tracks the state of a drag session — which files are being dragged,
/// their types, and the session lifecycle.
class DragSessionManager {

    // MARK: - Properties

    private(set) var currentFiles: [URL] = []
    private(set) var isActive: Bool = false
    private(set) var sessionStartTime: Date?

    // MARK: - Session Management

    func startSession(files: [URL]) {
        currentFiles = files
        isActive = true
        sessionStartTime = Date()
    }

    func endSession() {
        currentFiles = []
        isActive = false
        sessionStartTime = nil
    }

    /// Returns the primary file being dragged (first file)
    var primaryFile: URL? {
        currentFiles.first
    }

    /// Returns the file type of the primary file
    var primaryFileType: FileCategory? {
        guard let file = primaryFile else { return nil }
        return FileTypeDetector.detectType(for: file)
    }
}
