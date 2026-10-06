import Foundation

enum ClaudeUsageIntegration {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Glance", isDirectory: true)
    }
    static var cacheURL: URL { directory.appendingPathComponent("claude-usage.json") }

    /// Installed only by the user's Connect button. Existing status-line output
    /// and settings are preserved; only public rate_limits data is cached.
    static func install(home: URL = FileManager.default.homeDirectoryForCurrentUser, support: URL = directory) throws {
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        let configurationDirectory = settingsURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: configurationDirectory.path),
              let scriptURL = Bundle.module.url(forResource: "glance-claude-usage", withExtension: "pl") else { throw CocoaError(.fileNoSuchFile) }
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
            settings = decoded
        }
        let destination = support.appendingPathComponent("claude-statusline.pl")
        let previousURL = support.appendingPathComponent("claude-statusline-original.json")
        let command = "/usr/bin/perl " + shellQuote(destination.path)
        let previous = settings["statusLine"] as? [String: Any]
        if settings["statusLine"] != nil && previous == nil { throw CocoaError(.coderReadCorrupt) }
        if let previous, previous["command"] as? String == command { return }
        // Do not silently replace a status-line format we cannot preserve.
        if let previous, previous["type"] as? String != "command" { throw CocoaError(.coderReadCorrupt) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(contentsOf: scriptURL).write(to: destination, options: .atomic)
        try JSONSerialization.data(withJSONObject: previous ?? [:]).write(to: previousURL, options: .atomic)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try Data(contentsOf: settingsURL).write(to: support.appendingPathComponent("claude-settings-backup.json"), options: .atomic)
        }
        for url in [destination, previousURL, support.appendingPathComponent("claude-settings-backup.json")] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
        var statusLine = previous ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: settingsURL, options: .atomic)
    }

    private static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
