import Foundation

final class PTYTerminalService {
    private let fileManager = FileManager.default
    private let ptyProcess = PTYProcess()
    private var currentSessionDirectory: URL?

    func start(
        tool: ScriptTool,
        inputText: String,
        configURL: URL,
        extraEnv: [String: String] = [:],
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        stop()

        do {
            let sessionDirectory = try makeSessionDirectory()
            currentSessionDirectory = sessionDirectory

            let sessionScriptURL = try prepareScript(for: tool, in: sessionDirectory)
            try prepareInputFileIfNeeded(text: inputText, in: sessionDirectory)
            let runtimeConfigURL = try copyRuntimeConfig(from: configURL, to: sessionDirectory)
            let launcherURL = try writeLauncher(
                sessionDirectory: sessionDirectory,
                scriptURL: sessionScriptURL,
                runtimeConfigURL: runtimeConfigURL,
                extraEnv: extraEnv
            )

            try ptyProcess.start(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: [launcherURL.path],
                currentDirectoryURL: sessionDirectory,
                onOutput: onOutput,
                onExit: onExit
            )
        } catch {
            onOutput("[启动失败] \(error.localizedDescription)\n")
            onExit(-1)
        }
    }

    func send(_ text: String) {
        ptyProcess.send(text)
    }

    func stop() {
        ptyProcess.stop()
    }

    private func makeSessionDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ToolboxSessions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    private func prepareScript(for tool: ScriptTool, in sessionDirectory: URL) throws -> URL {
        let bundledScript = Bundle.main.resourceURL?
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent(tool.scriptRelativePath)
            
        if bundledScript == nil || !fileManager.fileExists(atPath: bundledScript!.path) {
            throw NSError(domain: "PTYTerminalService", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到脚本 \(tool.scriptRelativePath)"])
        }

        let destination = sessionDirectory.appendingPathComponent(tool.scriptRelativePath)
        try fileManager.copyItem(at: bundledScript!, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private func prepareInputFileIfNeeded(text: String, in sessionDirectory: URL) throws {
        let inputURL = sessionDirectory.appendingPathComponent("links.txt")
        try text.write(to: inputURL, atomically: true, encoding: .utf8)
    }

    private func copyRuntimeConfig(from sourceURL: URL, to sessionDirectory: URL) throws -> URL {
        let destination = sessionDirectory.appendingPathComponent("runtime.env")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private func writeLauncher(sessionDirectory: URL, scriptURL: URL, runtimeConfigURL: URL, extraEnv: [String: String]) throws -> URL {
        let launcherURL = sessionDirectory.appendingPathComponent("launch.sh")
        let binariesPath = Bundle.main.resourceURL?
            .appendingPathComponent("Binaries", isDirectory: true)
            .path ?? ""

        var script = """
        #!/bin/bash
        set -m # Enable job control to allow process groups
        """
        
        for (key, value) in extraEnv {
            script += "\nexport \(key)=\(shellQuote(value))"
        }

        script += """

        set -a
        if [ -f \(shellQuote(runtimeConfigURL.path)) ]; then
          . \(shellQuote(runtimeConfigURL.path))
        fi
        set +a
        export PATH=\(shellQuote(binariesPath)):"$PATH"
        cd \(shellQuote(sessionDirectory.path))
        exec /bin/bash \(shellQuote(scriptURL.path))
        """

        try script.write(to: launcherURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
        return launcherURL
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
