import Foundation

/// Sets up a temporary ZDOTDIR that chains the user's zsh config
/// then loads Flock shell enhancements (autosuggestions, etc.)
enum ShellEnhancer {
    /// Path to the bundled zsh-autosuggestions plugin
    private static var pluginPath: String? {
        // Check app bundle first, then fall back to Resources dir next to binary
        if let bundled = Bundle.main.path(forResource: "zsh-autosuggestions", ofType: "zsh") {
            return bundled
        }
        // Fallback: look relative to executable
        let execDir = (ProcessInfo.processInfo.arguments[0] as NSString).deletingLastPathComponent
        let relative = (execDir as NSString).appendingPathComponent("../Resources/zsh-autosuggestions.zsh")
        if FileManager.default.fileExists(atPath: relative) {
            return relative
        }
        return nil
    }

    /// Creates a temp ZDOTDIR and returns the environment array for startProcess.
    /// Returns nil if the shell isn't zsh or plugin isn't found.
    static func enhancedEnvironment(workingDirectory: String?) -> (env: [String], zdotdir: String)? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard shell.hasSuffix("/zsh") else { return nil }
        guard let plugin = pluginPath else { return nil }

        // Create temp ZDOTDIR
        let tmpBase = NSTemporaryDirectory() + "flock-shell"
        try? FileManager.default.createDirectory(atPath: tmpBase, withIntermediateDirectories: true)
        let zdotdir = tmpBase + "/\(ProcessInfo.processInfo.processIdentifier)-\(Int.random(in: 1000...9999))"
        try? FileManager.default.createDirectory(atPath: zdotdir, withIntermediateDirectories: true)

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()

        // .zshenv — chain user's .zshenv
        let zshenv = """
        [[ -f "\(home)/.zshenv" ]] && ZDOTDIR="\(home)" source "\(home)/.zshenv"
        """
        try? zshenv.write(toFile: zdotdir + "/.zshenv", atomically: true, encoding: .utf8)

        // .zshrc — chain user's .zshrc, then load enhancements
        let zshrc = """
        ZDOTDIR="\(home)"
        [[ -f "\(home)/.zshrc" ]] && source "\(home)/.zshrc"
        source "\(plugin)"
        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=244"
        ZSH_AUTOSUGGEST_STRATEGY=(history completion)
        """
        try? zshrc.write(toFile: zdotdir + "/.zshrc", atomically: true, encoding: .utf8)

        // Build environment array
        var env = ProcessInfo.processInfo.environment
        env["ZDOTDIR"] = zdotdir
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Flock"
        env["TERM_PROGRAM_VERSION"] = "1.0"
        if let dir = workingDirectory {
            env["HOME_OVERRIDE"] = dir  // not used, just for reference
        }
        let envArray = env.map { "\($0.key)=\($0.value)" }

        return (env: envArray, zdotdir: zdotdir)
    }

    /// Clean up a temp ZDOTDIR
    static func cleanup(zdotdir: String) {
        try? FileManager.default.removeItem(atPath: zdotdir)
    }
}
