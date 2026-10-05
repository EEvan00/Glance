import Foundation
import Darwin

/// Main-actor owned while running. Teardown storage is marked unsafe solely so
/// Swift 6.1 deinit can synchronously terminate its exclusively owned child.
@MainActor
final class JSONLineProcess {
    nonisolated(unsafe) private var process: Process?
    nonisolated(unsafe) private var output: FileHandle?
    nonisolated(unsafe) private var input: FileHandle?
    private var buffer = Data()
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var reachedEOF = false
    private var exitStatus: Int32?

    var isRunning: Bool { process?.isRunning == true }

    func start(executable: URL, arguments: [String], environment: [String: String]? = nil,
               timeout seconds: Double? = nil, keepsInputOpen: Bool = true,
               onLine: @escaping @MainActor (Data) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) throws {
        stop()
        let token = UUID()
        generation = token
        let child = Process()
        let stdout = Pipe()
        let stdin = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        if let environment { child.environment = environment }
        child.standardOutput = stdout
        // One-shot CLIs may consume stdin until EOF before running their action.
        child.standardInput = keepsInputOpen ? stdin.fileHandleForReading : FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        process = child
        output = stdout.fileHandleForReading
        input = keepsInputOpen ? stdin.fileHandleForWriting : nil
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return }
                    if data.isEmpty {
                        self.reachedEOF = true
                        self.finishIfDrained(onExit: onExit)
                        return
                    }
                    self.buffer.append(data)
                    guard self.buffer.count <= 1_048_576 else { self.stop(); onExit(-1); return }
                    while let newline = self.buffer.firstIndex(of: 10) {
                        let line = Data(self.buffer[..<newline])
                        self.buffer.removeSubrange(...newline)
                        if !line.isEmpty { onLine(line) }
                    }
                }
            }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.exitStatus = status
                self.finishIfDrained(onExit: onExit)
            }
        }
        do { try child.run() } catch { stop(); throw error }
        if let seconds {
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stop()
                onExit(-1)
            }
        }
    }

    private func finishIfDrained(onExit: @MainActor (Int32) -> Void) {
        guard reachedEOF, let status = exitStatus else { return }
        stop()
        onExit(status)
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input?.write(contentsOf: data)
    }

    func stop() {
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        if let process, process.isRunning {
            process.terminate()
            // Bounded cleanup even if the child ignores SIGTERM. No resident timer.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        output = nil
        input = nil
        buffer.removeAll(keepingCapacity: false)
        reachedEOF = false
        exitStatus = nil
    }

    deinit {
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
    }
}
