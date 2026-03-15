import Foundation

/// Manages a persistent Python subprocess running the ASR worker.
/// Communication happens via JSON‑line protocol over stdin/stdout.
final class ASRBridge {
    enum State: Equatable { case idle, downloading(Double), loading, ready, error(String) }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var readBuffer = Data()

    private let workerScript: String
    private let queue = DispatchQueue(label: "com.quiteecho.asr", qos: .userInitiated)

    init() {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/asr_worker.py",
            Bundle.main.bundlePath + "/../scripts/asr_worker.py",
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("scripts/asr_worker.py").path,
        ]
        workerScript = candidates.first(where: { fm.fileExists(atPath: $0) }) ?? "scripts/asr_worker.py"
    }

    // MARK: - Lifecycle

    func start(model: String, pythonPath: String = "", useHFMirror: Bool = false) {
        stop()
        setState(.loading)

        let proc = Process()

        let python = pythonPath.isEmpty ? resolvePython("") : pythonPath
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = [workerScript, model]

        var env = ProcessInfo.processInfo.environment
        if useHFMirror {
            env["HF_ENDPOINT"] = "https://hf-mirror.com"
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.readBuffer = Data()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.handleData(data) }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                NSLog("[ASR stderr] %@", line)
            }
        }

        proc.terminationHandler = { [weak self] p in
            NSLog("[ASR] Process exited with code %d", p.terminationStatus)
            DispatchQueue.main.async {
                self?.setState(.error("ASR process exited (\(p.terminationStatus))"))
            }
        }

        do {
            try proc.run()
            NSLog("[ASR] Started PID %d: %@", proc.processIdentifier, workerScript)
        } catch {
            NSLog("[ASR] Failed to start: %@", error.localizedDescription)
            setState(.error(error.localizedDescription))
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning { proc.terminate() }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        setState(.idle)
    }

    // MARK: - Commands

    func transcribe(audioPath: String, language: String?, completion: @escaping (Result<String, Error>) -> Void) {
        var req: [String: Any] = ["cmd": "transcribe", "audio": audioPath]
        if let lang = language, !lang.isEmpty { req["language"] = lang }
        send(req, responseHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    if let text = json["text"] as? String {
                        completion(.success(text))
                    } else if let err = json["error"] as? String {
                        completion(.failure(NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                    } else {
                        completion(.success(""))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        })
    }

    func reload(model: String) {
        setState(.loading)
        send(["cmd": "reload", "model": model])
    }

    // MARK: - Internal

    private var pendingHandler: ((Result<[String: Any], Error>) -> Void)?

    private func send(_ dict: [String: Any], responseHandler: ((Result<[String: Any], Error>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let pipe = self.stdinPipe else {
                responseHandler?(.failure(NSError(domain: "ASR", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not running"])))
                return
            }
            self.pendingHandler = responseHandler
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            pipe.fileHandleForWriting.write(line.data(using: .utf8)!)
        }
    }

    private func handleData(_ data: Data) {
        readBuffer.append(data)

        while let range = readBuffer.range(of: Data("\n".utf8)) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<range.lowerBound)
            readBuffer.removeSubrange(readBuffer.startIndex...range.lowerBound)

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            if let status = json["status"] as? String {
                DispatchQueue.main.async {
                    switch status {
                    case "downloading":
                        let progress = json["progress"] as? Double ?? 0
                        self.setState(.downloading(progress))
                    case "loading": self.setState(.loading)
                    case "ready":   self.setState(.ready)
                    default: break
                    }
                }
            }

            if let handler = pendingHandler, json["text"] != nil || json["error"] != nil {
                pendingHandler = nil
                handler(.success(json))
            }
        }
    }

    private func setState(_ s: State) {
        state = s
        onStateChange?(s)
    }

    // MARK: - Resolution

    private func resolvePython(_ configured: String) -> String {
        if !configured.isEmpty, FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".venv/bin/python3").path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "/usr/bin/python3"
    }

    deinit { stop() }
}
