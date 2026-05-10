import Foundation

public final class PTYProcess {
    private var process: Process?
    private var inputPipe: Pipe?

    public init() {}

    public func start(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws {
        stop()

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        let task = Process()
        
        // Use script command to spawn a PTY
        task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        task.arguments = ["-q", "/dev/null", executableURL.path] + arguments
        task.currentDirectoryURL = currentDirectoryURL
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stdoutPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let text = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self)
            onOutput(text)
        }

        task.terminationHandler = { [weak self] terminated in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self?.inputPipe = nil
            self?.process = nil
            onExit(terminated.terminationStatus)
        }

        try task.run()
        self.process = task
        self.inputPipe = stdinPipe
    }

    public func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
    }

    public func stop() {
        guard let process = process, process.isRunning else {
            self.process = nil
            self.inputPipe = nil
            return
        }

        let pid = pid_t(process.processIdentifier)
        // Use SIGTERM on the process group to ensure child shells/scripts are killed
        kill(-pid, SIGTERM)
        
        // Give it a moment to exit gracefully, then kill if needed
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak process] in
            guard let process = process, process.isRunning else { return }
            kill(-pid_t(process.processIdentifier), SIGKILL)
            process.terminate()
        }
        
        self.process = nil
        self.inputPipe = nil
    }
}
