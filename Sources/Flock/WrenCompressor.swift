import Foundation

/// Async wrapper around the Wren prompt compression CLI (~//wren/bin/wren).
/// Shells out to compress text, applies length and savings thresholds,
/// and returns the result on the main thread.
final class WrenCompressor {

    static let shared = WrenCompressor()

    private let wrenPath = NSHomeDirectory() + "/wren/bin/wren"
    private let minLength = 300
    private let minSavingsPercent = 20

    private init() {}

    /// Whether the wren binary exists and is executable.
    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: wrenPath)
    }

    /// Compress text asynchronously.
    /// Completion is called on the main thread with (text, savingsPercent).
    /// If compression is skipped or fails, returns the original text with nil savings.
    func compress(_ text: String, completion: @escaping (String, Int?) -> Void) {
        guard Settings.shared.wrenCompressionEnabled,
              isAvailable,
              text.count >= minLength else {
            DispatchQueue.main.async { completion(text, nil) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = runWren(text)
            DispatchQueue.main.async {
                guard let compressed = result,
                      !compressed.isEmpty else {
                    completion(text, nil)
                    return
                }

                let savings = (text.count - compressed.count) * 100 / text.count
                if savings >= self.minSavingsPercent {
                    completion(compressed, savings)
                } else {
                    completion(text, nil)
                }
            }
        }
    }

    private func runWren(_ text: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wrenPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return nil
        }

        inputPipe.fileHandleForWriting.write(Data(text.utf8))
        inputPipe.fileHandleForWriting.closeFile()

        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
