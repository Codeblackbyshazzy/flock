import Foundation

// MARK: - JournalActionType

enum JournalActionType: String, Codable {
    case fileRead
    case fileWrite
    case fileEdit
    case grep
    case glob
    case bash
    case finding
}

// MARK: - JournalEntry

struct JournalEntry: Codable, Identifiable {
    let id: UUID
    let paneId: UUID
    let paneName: String
    let actionType: JournalActionType
    let summary: String
    let filePaths: [String]
    let detail: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        paneId: UUID,
        paneName: String,
        actionType: JournalActionType,
        summary: String,
        filePaths: [String] = [],
        detail: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.paneId = paneId
        self.paneName = paneName
        self.actionType = actionType
        self.summary = summary
        self.filePaths = filePaths
        self.detail = detail
        self.timestamp = timestamp
    }
}

// MARK: - FlockJournal

final class FlockJournal {

    static let shared = FlockJournal()
    static let didChange = Notification.Name("FlockJournal.didChange")
    static let conflictDetected = Notification.Name("FlockJournal.conflictDetected")

    private(set) var entries: [JournalEntry] = []
    private var pruneTimer: Timer?

    private let fileURL: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Flock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.json")
    }()

    private init() {
        restore()
        startPruneTimer()
    }

    // MARK: - Logging

    func log(paneId: UUID, paneName: String, action: JournalActionType,
             summary: String, filePaths: [String] = [], detail: String? = nil) {
        guard Settings.shared.journalEnabled else { return }

        let entry = JournalEntry(
            paneId: paneId,
            paneName: paneName,
            actionType: action,
            summary: summary,
            filePaths: filePaths,
            detail: detail
        )
        entries.append(entry)
        didMutate()

        // Check for write conflicts
        if action == .fileWrite || action == .fileEdit {
            checkConflicts(for: entry)
        }
    }

    // MARK: - Queries

    func entries(forPane paneId: UUID) -> [JournalEntry] {
        entries.filter { $0.paneId == paneId }
    }

    func entries(touchingFile path: String) -> [JournalEntry] {
        entries.filter { $0.filePaths.contains(path) }
    }

    func entries(ofType type: JournalActionType) -> [JournalEntry] {
        entries.filter { $0.actionType == type }
    }

    func recentEntries(limit: Int = 50) -> [JournalEntry] {
        Array(entries.suffix(limit))
    }

    /// Returns entries from other panes that touched the same file.
    func panesConflicting(withFile path: String, excludingPane: UUID) -> [JournalEntry] {
        entries.filter { $0.filePaths.contains(path) && $0.paneId != excludingPane }
    }

    // MARK: - Context Generation

    /// Generates a compact markdown briefing of recent agent activity,
    /// excluding entries from the given pane.
    func contextBriefing(excludingPane paneId: UUID) -> String? {
        let relevant = entries.filter { $0.paneId != paneId }
        guard !relevant.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("## Recent Agent Activity")
        lines.append("")
        lines.append("Other Flock agents have recently performed these actions:")
        lines.append("")

        // Group by pane
        let grouped = Dictionary(grouping: relevant.suffix(30), by: { $0.paneName })
        for (paneName, paneEntries) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("### \(paneName)")
            for entry in paneEntries.suffix(10) {
                let ago = formatTimeAgo(entry.timestamp)
                lines.append("- [\(ago)] \(entry.summary)")
            }
            lines.append("")
        }

        // Deduplicated file list
        let allFiles = Set(relevant.flatMap { $0.filePaths })
        if !allFiles.isEmpty {
            lines.append("### Files touched by other agents")
            for file in allFiles.sorted().prefix(20) {
                lines.append("- `\(file)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Conflict Detection

    private func checkConflicts(for entry: JournalEntry) {
        for filePath in entry.filePaths {
            let conflicts = entries.filter {
                $0.id != entry.id
                    && $0.paneId != entry.paneId
                    && $0.filePaths.contains(filePath)
                    && ($0.actionType == .fileWrite || $0.actionType == .fileEdit)
            }
            guard !conflicts.isEmpty else { continue }

            let conflictingNames = Array(Set(conflicts.map { $0.paneName }))
            NotificationCenter.default.post(
                name: FlockJournal.conflictDetected,
                object: nil,
                userInfo: [
                    "filePath": filePath,
                    "paneId": entry.paneId,
                    "conflictingPanes": conflictingNames,
                ]
            )
        }
    }

    // MARK: - Cleanup

    func prune(olderThan interval: TimeInterval? = nil) {
        let ttl = interval ?? TimeInterval(Settings.shared.journalTTLMinutes * 60)
        let cutoff = Date().addingTimeInterval(-ttl)
        let before = entries.count
        entries.removeAll { $0.timestamp < cutoff }
        if entries.count != before { didMutate() }
    }

    func clear() {
        entries.removeAll()
        didMutate()
    }

    // MARK: - Persistence

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([JournalEntry].self, from: data) else { return }
        entries = loaded
    }

    private func didMutate() {
        save()
        NotificationCenter.default.post(name: FlockJournal.didChange, object: self)
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    // MARK: - Helpers

    // MARK: - Render

    /// Writes journal output to a temp file and returns the path.
    func renderToTempFile() -> String {
        var lines: [String] = []

        if entries.isEmpty {
            lines.append("Journal is empty.")
        } else {
            lines.append("\u{1B}[1mFlock Journal\u{1B}[0m  (\(entries.count) entries)\n")
            lines.append("    Time  Pane                  Action      Summary")
            lines.append(String(repeating: "-", count: 78))

            let timeFmt = DateFormatter()
            timeFmt.dateFormat = "HH:mm:ss"

            for entry in entries {
                let time = timeFmt.string(from: entry.timestamp)
                let pane = String(entry.paneName.prefix(20))
                let action = entry.actionType.rawValue
                let padPane = pane.padding(toLength: 20, withPad: " ", startingAt: 0)
                let padAction = action.padding(toLength: 10, withPad: " ", startingAt: 0)
                lines.append("\(time)  \(padPane)  \(padAction)  \(entry.summary)")
                for file in entry.filePaths {
                    lines.append("           \u{1B}[2m-> \(file)\u{1B}[0m")
                }
            }
        }

        let output = lines.joined(separator: "\n") + "\n"
        let tmpPath = NSTemporaryDirectory() + "flock-journal.txt"
        try? output.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        return tmpPath
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
