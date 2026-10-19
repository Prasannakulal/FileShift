import Foundation

/// Tracks the state and progress of a file conversion task
class ConversionTask: ObservableObject, Identifiable {
    let id = UUID()
    let sourceFile: URL
    let targetFormat: String
    let startTime: Date

    @Published var status: Status = .pending
    @Published var progress: Double = 0.0
    @Published var outputFile: URL?
    @Published var errorMessage: String?

    enum Status: String {
        case pending
        case converting
        case completed
        case failed
    }

    init(sourceFile: URL, targetFormat: String) {
        self.sourceFile = sourceFile
        self.targetFormat = targetFormat
        self.startTime = Date()
    }
}
