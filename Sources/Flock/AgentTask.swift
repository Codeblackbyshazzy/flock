import Foundation

// MARK: - TaskStatus

enum TaskStatus: String, Codable {
    case backlog
    case inProgress
    case done
    case failed
}

// MARK: - AgentActionType

enum AgentActionType: String, Codable {
    case think
    case read
    case edit
    case write
    case bash
    case search
    case agent
    case web
    case message

    var badge: String {
        switch self {
        case .think:   return "..."
        case .read:    return "R"
        case .edit:    return "E"
        case .write:   return "W"
        case .bash:    return "$"
        case .search:  return "?"
        case .agent:   return "A"
        case .web:     return "W"
        case .message: return ">"
        }
    }

}

// MARK: - AgentTaskAction

struct AgentTaskAction: Codable, Identifiable {
    let id: UUID
    let type: AgentActionType
    let title: String
    let detail: String?
    let timestamp: Date
    var isActive: Bool

    init(
        id: UUID = UUID(),
        type: AgentActionType,
        title: String,
        detail: String? = nil,
        timestamp: Date = Date(),
        isActive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.isActive = isActive
    }
}

// MARK: - AgentTask

final class AgentTask: Codable, Identifiable {
    let id: UUID
    var title: String
    var status: TaskStatus
    var actions: [AgentTaskAction]
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
    var resultSummary: String?
    var costUsd: Double?
    var sessionId: String?
    /// Transient -- not persisted. True when the process has exited but the session is alive.
    var isWaitingForInput: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, title, status, actions, createdAt, startedAt, completedAt
        case errorMessage, resultSummary, costUsd, sessionId
    }

    var elapsedTime: TimeInterval {
        guard let start = startedAt else { return 0 }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .backlog,
        actions: [AgentTaskAction] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        resultSummary: String? = nil,
        costUsd: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.actions = actions
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.resultSummary = resultSummary
        self.costUsd = costUsd
    }
}

// MARK: - TaskStore

final class TaskStore {

    static let shared = TaskStore()
    static let didChange = Notification.Name("TaskStore.didChange")

    private(set) var tasks: [AgentTask] = []

    private let fileURL: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Flock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks.json")
    }()

    private init() {
        restore()
    }

    // MARK: Filtered accessors

    var backlog: [AgentTask] {
        tasks.filter { $0.status == .backlog }
    }

    var inProgress: [AgentTask] {
        tasks.filter { $0.status == .inProgress }
    }

    var done: [AgentTask] {
        tasks.filter { $0.status == .done }
    }

    // MARK: Mutations

    func add(_ task: AgentTask) {
        tasks.append(task)
        didMutate()
    }

    func remove(_ task: AgentTask) {
        tasks.removeAll { $0.id == task.id }
        didMutate()
    }

    func moveToInProgress(_ task: AgentTask) {
        task.status = .inProgress
        task.startedAt = task.startedAt ?? Date()
        didMutate()
    }

    func markDone(_ task: AgentTask, summary: String?, cost: Double?) {
        task.status = .done
        task.completedAt = Date()
        task.resultSummary = summary
        task.costUsd = cost
        didMutate()
    }

    func markFailed(_ task: AgentTask, error: String) {
        task.status = .failed
        task.completedAt = Date()
        task.errorMessage = error
        didMutate()
    }

    func reorder(in column: TaskStatus, from source: IndexSet, to destination: Int) {
        var columnTasks = tasks.filter { $0.status == column }
        columnTasks.move(fromOffsets: source, toOffset: destination)

        // Rebuild tasks preserving order of other columns
        var result: [AgentTask] = []
        var columnIterator = columnTasks.makeIterator()

        for task in tasks {
            if task.status == column {
                if let next = columnIterator.next() {
                    result.append(next)
                }
            } else {
                result.append(task)
            }
        }
        tasks = result
        didMutate()
    }

    // MARK: Persistence

    private func didMutate() {
        save()
        NotificationCenter.default.post(name: TaskStore.didChange, object: self)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func restore() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([AgentTask].self, from: data) else { return }
        tasks = loaded

        // Tasks that were in-progress when the app quit have no running process.
        // Mark them as failed so they don't sit in a stale state.
        for task in tasks where task.status == .inProgress {
            task.status = .failed
            task.completedAt = Date()
            task.errorMessage = "Interrupted (app quit)"
        }
    }
}
