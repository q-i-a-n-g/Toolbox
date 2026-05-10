import Foundation

// Copying the PTYProcess class here for CLI test since it is part of an Xcode project
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
        guard let process else { return }

        process.interrupt()
        if process.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
            }
        }
    }
}

let semaphore = DispatchSemaphore(value: 0)
let pty = PTYProcess()

print("Starting PTY test with 'ls -l /'...")

do {
    try pty.start(
        executableURL: URL(fileURLWithPath: "/bin/ls"),
        arguments: ["-l", "/"],
        currentDirectoryURL: nil,
        onOutput: { text in
            print("[OUTPUT] \(text)", terminator: "")
        },
        onExit: { status in
            print("\n[EXIT] Status: \(status)")
            semaphore.signal()
        }
    )
} catch {
    print("Error: \(error)")
    semaphore.signal()
}

semaphore.wait()
print("Test finished.")
