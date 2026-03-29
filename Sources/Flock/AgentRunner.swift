import Foundation

// MARK: - AgentProcess

/// Wraps a single Claude Code process for one AgentTask.
final class AgentProcess {

    let task: AgentTask
    private(set) var process: Process?
    private let parser = StreamJsonParser()
    private let outputPipe = Pipe()
    private let inputPipe = Pipe()
    private let parserQueue = DispatchQueue(label: "com.baa.flock.parser")
    private let resumeSessionId: String?
    private let resumeMessage: String?

    var onEvent: ((StreamJsonEvent) -> Void)?
    var onComplete: (((isError: Bool, text: String?, costUsd: Double?)) -> Void)?

    init(task: AgentTask, resumeSessionId: String? = nil, message: String? = nil) {
        self.task = task
        self.resumeSessionId = resumeSessionId
        self.resumeMessage = message
    }

    // MARK: - Launch

    func launch() {
        guard let claudePath = Self.findClaudeBinary() else {
            let result = (isError: true, text: "claude binary not found" as String?, costUsd: nil as Double?)
            onComplete?(result)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        if let sessionId = resumeSessionId, let message = resumeMessage {
            // Resume an existing conversation
            proc.arguments = ["-p", message, "--resume", sessionId, "--output-format", "stream-json", "--verbose"]
        } else {
            // New conversation
            proc.arguments = ["-p", task.title, "--output-format", "stream-json", "--verbose"]
        }
        proc.standardOutput = outputPipe
        proc.standardInput = inputPipe
        proc.standardError = FileHandle.nullDevice
        proc.environment = ProcessInfo.processInfo.environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.parserQueue.async { self?.handleData(data) }
        }

        proc.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            self.outputPipe.fileHandleForReading.readabilityHandler = nil
            // Drain remaining data on the serial queue to avoid racing with readabilityHandler
            self.parserQueue.async {
                let remaining = self.outputPipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    self.handleData(remaining)
                }

                self.outputPipe.fileHandleForReading.closeFile()
                self.inputPipe.fileHandleForWriting.closeFile()

                let finalResult = self.parser.finalResult()
                    ?? (isError: self.process?.terminationStatus != 0,
                        text: nil as String?,
                        costUsd: nil as Double?)

                DispatchQueue.main.async {
                    self.onComplete?(finalResult)
                }
            }
        }

        self.process = proc

        do {
            try proc.run()
        } catch {
            let result = (isError: true, text: "Failed to launch: \(error.localizedDescription)" as String?, costUsd: nil as Double?)
            onComplete?(result)
        }
    }

    // MARK: - Send Message

    /// Writes a follow-up message to the running Claude process's stdin.
    func sendMessage(_ text: String) {
        guard let proc = process, proc.isRunning else { return }
        let data = Data((text + "\n").utf8)
        inputPipe.fileHandleForWriting.write(data)
    }

    // MARK: - Terminate

    func terminate() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
    }

    // MARK: - Private

    private func handleData(_ data: Data) {
        parser.feed(data) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onEvent?(event)
            }
        }
    }

    /// Finds the claude binary, checking the known install path first then PATH.
    private static func findClaudeBinary() -> String? {
        let knownPath = NSHomeDirectory() + "/.local/bin/claude"
        if FileManager.default.isExecutableFile(atPath: knownPath) {
            return knownPath
        }

        // Search PATH
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/claude"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - AgentRunner

/// Singleton that manages running Claude Code agent processes.
/// Coordinates task lifecycle: backlog -> inProgress -> done/failed.
final class AgentRunner {

    static let shared = AgentRunner()

    private(set) var runningProcesses: [UUID: AgentProcess] = [:]

    var activeCount: Int { runningProcesses.count }

    private init() {}

    // MARK: - Scheduling

    /// Starts the next backlog task if capacity allows.
    func scheduleNext() {
        let maxParallel = Settings.shared.maxParallelAgents
        while activeCount < maxParallel {
            guard let nextTask = TaskStore.shared.backlog.first else { break }
            start(nextTask)
        }
    }

    // MARK: - Start

    /// Creates an AgentProcess for the task, moves it to inProgress, and launches.
    func start(_ task: AgentTask) {
        guard runningProcesses[task.id] == nil else { return }
        TaskStore.shared.moveToInProgress(task)
        wireAndLaunch(AgentProcess(task: task), for: task)
    }

    /// Resumes a conversation by spawning a new process with --resume.
    func resume(_ task: AgentTask, message: String) {
        guard runningProcesses[task.id] == nil,
              let sessionId = task.sessionId else { return }
        wireAndLaunch(AgentProcess(task: task, resumeSessionId: sessionId, message: message), for: task)
        NotificationCenter.default.post(name: TaskStore.didChange, object: nil)
    }

    private func wireAndLaunch(_ agentProcess: AgentProcess, for task: AgentTask) {
        runningProcesses[task.id] = agentProcess
        task.isWaitingForInput = false
        agentProcess.onEvent = { [weak self] event in
            self?.handleEvent(event, for: task)
        }
        agentProcess.onComplete = { [weak self] result in
            self?.handleCompletion(result, for: task)
        }
        agentProcess.launch()
    }

    /// Marks a waiting task as done (user explicitly finishing the conversation).
    func finish(_ task: AgentTask) {
        if let agentProcess = runningProcesses[task.id] {
            agentProcess.terminate()
            runningProcesses.removeValue(forKey: task.id)
        }
        TaskStore.shared.markDone(task, summary: task.resultSummary, cost: task.costUsd)
    }

    // MARK: - Send Message

    /// Sends a follow-up message to the agent. If the process is still running,
    /// writes to stdin. If it has completed (waiting for input), spawns a new
    /// process with --resume to continue the conversation.
    func sendMessage(to task: AgentTask, text: String) {
        // Add user message to the action timeline
        for i in task.actions.indices where task.actions[i].isActive {
            task.actions[i].isActive = false
        }
        let action = AgentTaskAction(type: .message, title: text, isActive: false)
        task.actions.append(action)
        NotificationCenter.default.post(name: TaskStore.didChange, object: nil)

        if let proc = runningProcesses[task.id] {
            // Process still running -- write to stdin
            proc.sendMessage(text)
        } else if task.sessionId != nil && task.status == .inProgress {
            // Process exited but session alive -- resume conversation
            resume(task, message: text)
        }
    }

    // MARK: - Cancel

    /// Terminates and marks a single task as failed.
    func cancel(_ task: AgentTask) {
        if let agentProcess = runningProcesses[task.id] {
            agentProcess.terminate()
            runningProcesses.removeValue(forKey: task.id)
        }
        task.isWaitingForInput = false
        TaskStore.shared.markFailed(task, error: "Cancelled by user")
    }

    /// Terminates all running processes.
    func cancelAll() {
        let ids = Array(runningProcesses.keys)
        for id in ids {
            guard let agentProcess = runningProcesses[id] else { continue }
            agentProcess.terminate()
            runningProcesses.removeValue(forKey: id)
            TaskStore.shared.markFailed(agentProcess.task, error: "Cancelled (all)")
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: StreamJsonEvent, for task: AgentTask) {
        switch event {
        case .toolUse(let name, let input):
            deactivatePreviousAction(for: task)

            let actionType = mapToolName(name)
            let title = formatToolTitle(name: name, input: input)
            let action = AgentTaskAction(
                type: actionType,
                title: title,
                detail: name,
                timestamp: Date(),
                isActive: true
            )
            task.actions.append(action)
            NotificationCenter.default.post(name: TaskStore.didChange, object: nil)

        case .thinking(let text):
            deactivatePreviousAction(for: task)

            let truncated = text.count > 80 ? String(text.prefix(80)) + "..." : text
            let action = AgentTaskAction(
                type: .think,
                title: truncated,
                detail: text,
                timestamp: Date(),
                isActive: true
            )
            task.actions.append(action)
            NotificationCenter.default.post(name: TaskStore.didChange, object: nil)

        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 3 else { break }
            deactivatePreviousAction(for: task)
            let short = trimmed.count > 80 ? String(trimmed.prefix(80)) + "..." : trimmed
            let action = AgentTaskAction(
                type: .think,
                title: short,
                detail: trimmed,
                timestamp: Date(),
                isActive: true
            )
            task.actions.append(action)
            NotificationCenter.default.post(name: TaskStore.didChange, object: nil)

        case .result:
            // Handled by onComplete
            break

        case .init_(let sessionId, _):
            // Capture session ID for conversation resumption
            if !sessionId.isEmpty {
                task.sessionId = sessionId
            }

        case .toolResult:
            // Tool results are internal to the stream -- no action needed
            break
        }
    }

    private func handleCompletion(
        _ result: (isError: Bool, text: String?, costUsd: Double?),
        for task: AgentTask
    ) {
        runningProcesses.removeValue(forKey: task.id)

        deactivatePreviousAction(for: task)

        // Accumulate cost across conversation rounds
        if let newCost = result.costUsd {
            task.costUsd = (task.costUsd ?? 0) + newCost
        }

        if result.isError {
            task.isWaitingForInput = false
            TaskStore.shared.markFailed(task, error: result.text ?? "Unknown error")
        } else if task.sessionId != nil {
            // Session exists -- keep task alive for follow-up messages
            task.resultSummary = result.text
            task.isWaitingForInput = true
            NotificationCenter.default.post(name: TaskStore.didChange, object: nil)
        } else {
            // No session -- one-shot completion
            TaskStore.shared.markDone(task, summary: result.text, cost: task.costUsd)

            if Settings.shared.memoryEnabled, let summary = result.text, !summary.isEmpty {
                MemoryStore.shared.addTaskSummary(
                    taskTitle: task.title,
                    summary: summary,
                    cost: task.costUsd
                )
            }
        }

        scheduleNext()
    }

    private func deactivatePreviousAction(for task: AgentTask) {
        if let lastIndex = task.actions.lastIndex(where: { $0.isActive }) {
            task.actions[lastIndex].isActive = false
        }
    }
}

// MARK: - Tool Name Mapping

/// Maps a Claude Code tool name to an AgentActionType.
func mapToolName(_ name: String) -> AgentActionType {
    switch name {
    case "Read":
        return .read
    case "Edit":
        return .edit
    case "Write":
        return .write
    case "Bash":
        return .bash
    case "Grep", "Glob":
        return .search
    case "Agent", "Skill":
        return .agent
    case "WebSearch", "WebFetch":
        return .web
    default:
        return .bash
    }
}

/// Extracts a human-readable title from the tool name and its input dictionary.
func formatToolTitle(name: String, input: [String: Any]) -> String {
    switch name {
    case "Read", "Edit", "Write":
        if let filePath = input["file_path"] as? String {
            let filename = (filePath as NSString).lastPathComponent
            return "\(name) \(filename)"
        }
        return name

    case "Bash":
        if let command = input["command"] as? String {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 50 {
                return String(trimmed.prefix(50)) + "..."
            }
            return trimmed
        }
        return "Bash"

    case "Grep", "Glob":
        if let pattern = input["pattern"] as? String {
            return "\(name) \(pattern)"
        }
        return name

    case "Agent", "Skill":
        if let description = input["description"] as? String {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 60 {
                return String(trimmed.prefix(60)) + "..."
            }
            return trimmed
        }
        if let skill = input["skill"] as? String {
            return "Skill: \(skill)"
        }
        return name

    case "WebSearch", "WebFetch":
        if let query = input["query"] as? String {
            return "Search: \(query)"
        }
        if let url = input["url"] as? String {
            return "Fetch: \(url)"
        }
        return name

    default:
        return name
    }
}
