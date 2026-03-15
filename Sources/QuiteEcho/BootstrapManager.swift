import Foundation

/// Manages the Python virtual environment and dependency installation
/// in ~/Library/Application Support/QuiteEcho/.
final class BootstrapManager {
    enum State: Equatable {
        case idle, checking, creatingVenv, installingDeps, ready, error(String)
    }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    /// Path to the bootstrapped Python interpreter.
    var pythonPath: String { supportDir.appendingPathComponent(".venv/bin/python3").path }

    /// Path to the uv binary bundled in Resources.
    private var uvPath: String {
        Bundle.main.bundlePath + "/Contents/Resources/uv"
    }

    private let supportDir: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuiteEcho")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let venvDir: URL
    private let markerFile: URL  // tracks installed dependency versions

    private let queue = DispatchQueue(label: "com.quiteecho.bootstrap", qos: .userInitiated)

    init() {
        venvDir = supportDir.appendingPathComponent(".venv")
        markerFile = supportDir.appendingPathComponent(".deps-installed")
    }

    // MARK: - Public

    /// Ensure the venv and dependencies are ready. Calls completion on main thread.
    func ensureReady(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                setState(.checking)

                let fm = FileManager.default

                // 1. Create venv if missing
                if !fm.fileExists(atPath: venvDir.appendingPathComponent("bin/python3").path) {
                    setState(.creatingVenv)
                    try runUV(["venv", "--python", "3.13", venvDir.path])
                }

                // 2. Install/upgrade deps if needed
                let requiredDeps = "qwen-asr>=0.0.6 torch>=2.0"
                let currentMarker = (try? String(contentsOf: markerFile, encoding: .utf8)) ?? ""

                if currentMarker.trimmingCharacters(in: .whitespacesAndNewlines) != requiredDeps {
                    setState(.installingDeps)
                    try runUV([
                        "pip", "install",
                        "--python", venvDir.appendingPathComponent("bin/python3").path,
                        "qwen-asr>=0.0.6", "torch>=2.0",
                    ])
                    try requiredDeps.write(to: markerFile, atomically: true, encoding: .utf8)
                }

                setState(.ready)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                let msg = error.localizedDescription
                setState(.error(msg))
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Internal

    private func runUV(_ arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: uvPath)
        proc.arguments = arguments
        proc.environment = ProcessInfo.processInfo.environment

        let errPipe = Pipe()
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Bootstrap", code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "uv failed: \(stderr)"]
            )
        }
    }

    private func setState(_ s: State) {
        state = s
        DispatchQueue.main.async { self.onStateChange?(s) }
    }
}
