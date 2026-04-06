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
            inputPipe.fileHandleForReading.closeFile()
            inputPipe.fileHandleForWriting.closeFile()
            outputPipe.fileHandleForReading.closeFile()
            outputPipe.fileHandleForWriting.closeFile()
            return nil
        }

        // Write stdin on a background thread to avoid deadlock when input exceeds pipe buffer
        // (the child may block writing stdout while we block writing stdin)
        let inputData = Data(text.utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            inputPipe.fileHandleForWriting.write(inputData)
            inputPipe.fileHandleForWriting.closeFile()
        }

        // Read output BEFORE waiting for exit to avoid deadlock when output exceeds pipe buffer
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        outputPipe.fileHandleForReading.closeFile()

        // Timeout: kill if still running after 10 seconds
        let deadline = DispatchTime.now() + .seconds(10)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
            if proc.isRunning { proc.terminate() }
        }

        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else { return nil }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
