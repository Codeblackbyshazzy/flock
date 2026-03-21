import Foundation

struct SessionPane: Codable {
    let type: String        // "claude" or "shell"
    let workingDirectory: String?
    let customName: String?
}

struct SessionLayout: Codable {
    let panes: [SessionPane]
    let activeIndex: Int
}

enum SessionRestore {
    private static var sessionURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Flock")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func save(panes: [(type: String, directory: String?, name: String?)], activeIndex: Int) {
        let layout = SessionLayout(
            panes: panes.map { SessionPane(type: $0.type, workingDirectory: $0.directory, customName: $0.name) },
            activeIndex: activeIndex
        )
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: sessionURL)
        }
    }

    static func restore() -> SessionLayout? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(SessionLayout.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: sessionURL)
    }
}
