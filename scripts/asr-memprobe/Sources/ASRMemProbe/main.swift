import Foundation
import Darwin
import MLXAudioSTT
import MLXAudioCore
import MLX

// MARK: - Memory sampling

/// phys_footprint (matches Activity Monitor "Memory" column).
func physFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kerr == KERN_SUCCESS ? info.phys_footprint : 0
}

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return kerr == KERN_SUCCESS ? info.resident_size : 0
}

func fmtMB(_ bytes: UInt64) -> String {
    String(format: "%7.1f MB", Double(bytes) / 1_048_576.0)
}

func fmtGB(_ bytes: UInt64) -> String {
    String(format: "%5.2f GB", Double(bytes) / 1_073_741_824.0)
}

// 1 second of silence @ 16 kHz is enough to trigger a full forward pass.
func syntheticAudio(seconds: Double = 1.0, sampleRate: Int = 16_000) -> MLXArray {
    let n = Int(seconds * Double(sampleRate))
    return MLXArray(Array(repeating: Float(0), count: n))
}

// MARK: - Cache check

func isCached(_ modelId: String) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let flatId = modelId.replacingOccurrences(of: "/", with: "--")
    let path = "\(home)/.cache/huggingface/hub/models--\(flatId)"
    return FileManager.default.fileExists(atPath: path)
}

// MARK: - Experiment mode: measure clearCache effect on memory + latency

func experimentChild(_ modelId: String) async {
    setbuf(stdout, nil)
    print("═══════════════════════════════════════════════════════════")
    print("clearCache experiment: \(modelId)")
    print("═══════════════════════════════════════════════════════════")

    let base = physFootprintBytes()
    print(String(format: "phase 0  baseline           %8.1f MB", Double(base) / 1_048_576))

    let t0 = Date()
    let model: Qwen3ASRModel
    do {
        model = try await Qwen3ASRModel.fromPretrained(modelId)
    } catch {
        print("❌ load failed: \(error.localizedDescription)")
        return
    }
    let loadSec = Date().timeIntervalSince(t0)
    let loaded = physFootprintBytes()
    print(String(format: "phase 1  after load         %8.1f MB   load=%.2fs", Double(loaded) / 1_048_576, loadSec))

    let audio = syntheticAudio(seconds: 1.0)

    // Phase 2: cold inference (includes Metal JIT compile)
    let t2start = Date()
    _ = model.generate(audio: audio)
    let t1 = Date().timeIntervalSince(t2start)
    let fp1 = physFootprintBytes()
    print(String(format: "phase 2  cold inference     %8.1f MB   infer=%.3fs  (JIT compile)", Double(fp1) / 1_048_576, t1))

    // Phase 3: warm inference (cached kernels + buffers)
    let t3start = Date()
    _ = model.generate(audio: audio)
    let t2 = Date().timeIntervalSince(t3start)
    let fp2 = physFootprintBytes()
    print(String(format: "phase 3  warm inference     %8.1f MB   infer=%.3fs", Double(fp2) / 1_048_576, t2))

    // Phase 4: clear cache
    MLX.GPU.clearCache()
    let afterClear = physFootprintBytes()
    let freed = Int64(fp2) - Int64(afterClear)
    print(String(format: "phase 4  after clearCache   %8.1f MB   freed=%+.1f MB",
                 Double(afterClear) / 1_048_576, Double(freed) / 1_048_576))

    // Phase 5: inference after clearCache (kernels warm, buffers re-allocated)
    let t5start = Date()
    _ = model.generate(audio: audio)
    let t3 = Date().timeIntervalSince(t5start)
    let fp3 = physFootprintBytes()
    print(String(format: "phase 5  post-clear infer   %8.1f MB   infer=%.3fs  (buffers re-allocated)", Double(fp3) / 1_048_576, t3))

    // Phase 6: warm again
    let t6start = Date()
    _ = model.generate(audio: audio)
    let t4 = Date().timeIntervalSince(t6start)
    let fp4 = physFootprintBytes()
    print(String(format: "phase 6  warm again         %8.1f MB   infer=%.3fs", Double(fp4) / 1_048_576, t4))

    print("\nLatency summary (seconds):")
    print(String(format: "  1st inference (cold JIT):    %.3f", t1))
    print(String(format: "  2nd inference (fully warm):  %.3f", t2))
    print(String(format: "  3rd (after clearCache):      %.3f   Δ vs warm = %+.3f", t3, t3 - t2))
    print(String(format: "  4th (warm again):            %.3f", t4))

    print("\nMemory summary (phys_footprint):")
    print(String(format: "  weights only (phase 1):      %.0f MB", Double(loaded) / 1_048_576))
    print(String(format: "  with cached activations:     %.0f MB", Double(fp2) / 1_048_576))
    print(String(format: "  after clearCache:            %.0f MB   (weights + %.0f MB residual)",
                 Double(afterClear) / 1_048_576, Double(Int64(afterClear) - Int64(loaded)) / 1_048_576))

    let saved = Int64(fp2) - Int64(afterClear)
    let latencyPenalty = (t3 - t2) * 1000  // ms
    print("\nVerdict:")
    print(String(format: "  clearCache frees %.0f MB at a cost of %+.0f ms on the next inference.",
                 Double(saved) / 1_048_576, latencyPenalty))
}

// MARK: - Child mode: probe a single model and print a CSV line

func probeChild(_ modelId: String) async {
    let base = physFootprintBytes()
    let t0 = Date()
    do {
        let model = try await Qwen3ASRModel.fromPretrained(modelId)
        let loaded = physFootprintBytes()
        let loadedRSS = residentBytes()
        let loadSec = Date().timeIntervalSince(t0)

        let audio = syntheticAudio(seconds: 1.0)
        _ = model.generate(audio: audio)

        let peak = physFootprintBytes()
        let peakRSS = residentBytes()

        // CSV: id,base,loaded,peak,loadedRSS,peakRSS,loadSec
        print("RESULT,\(modelId),\(base),\(loaded),\(peak),\(loadedRSS),\(peakRSS),\(loadSec)")
    } catch {
        print("ERROR,\(modelId),\(error.localizedDescription)")
    }
}

// MARK: - Parent mode: spawn one subprocess per model

struct ProbeResult {
    let modelId: String
    let baseline: UInt64
    let loaded: UInt64
    let peak: UInt64
    let loadedRSS: UInt64
    let peakRSS: UInt64
    let loadSec: Double
}

func runChild(_ modelId: String, binaryPath: String) -> ProbeResult? {
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Probing \(modelId)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: binaryPath)
    proc.arguments = ["--one", modelId]

    let outPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = FileHandle.standardError

    do {
        try proc.run()
    } catch {
        print("  failed to spawn: \(error.localizedDescription)")
        return nil
    }
    proc.waitUntilExit()

    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    print(output, terminator: "")

    // Parse the RESULT line.
    for line in output.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: ",").map(String.init)
        if parts.count == 8, parts[0] == "RESULT" {
            guard let base = UInt64(parts[2]),
                  let loaded = UInt64(parts[3]),
                  let peak = UInt64(parts[4]),
                  let loadedRSS = UInt64(parts[5]),
                  let peakRSS = UInt64(parts[6]),
                  let loadSec = Double(parts[7]) else { continue }
            let r = ProbeResult(
                modelId: parts[1],
                baseline: base,
                loaded: loaded,
                peak: peak,
                loadedRSS: loadedRSS,
                peakRSS: peakRSS,
                loadSec: loadSec
            )
            print("  baseline  phys_footprint = \(fmtMB(base))")
            print("  loaded    phys_footprint = \(fmtMB(loaded))  (+\(fmtMB(loaded &- base)))  rss=\(fmtMB(loadedRSS))  load=\(String(format: "%.1fs", loadSec))")
            print("  peak      phys_footprint = \(fmtMB(peak))  (+\(fmtMB(peak &- loaded)) after inference)  rss=\(fmtMB(peakRSS))")
            return r
        }
        if parts.count >= 3, parts[0] == "ERROR" {
            print("  child reported error: \(parts.dropFirst(2).joined(separator: ","))")
            return nil
        }
    }
    print("  ⚠️  child exited without RESULT line (code=\(proc.terminationStatus))")
    return nil
}

// MARK: - Entry point

let args = CommandLine.arguments

if args.count >= 3 && args[1] == "--one" {
    await probeChild(args[2])
    exit(0)
}

if args.count >= 3 && args[1] == "--experiment" {
    await experimentChild(args[2])
    exit(0)
}

let probeAll = args.contains("--all")
let allVariants = ["bf16", "8bit", "6bit", "4bit"]
let families = ["Qwen3-ASR-0.6B", "Qwen3-ASR-1.7B"]
let binaryPath = args[0]

var targets: [String] = []
for family in families {
    for variant in allVariants {
        let id = "mlx-community/\(family)-\(variant)"
        if !probeAll && !isCached(id) {
            print("skip (not cached): \(id)")
            continue
        }
        targets.append(id)
    }
}

print("\nWill probe \(targets.count) model(s) in isolated subprocesses.\n")

var results: [ProbeResult] = []
for id in targets {
    if let r = runChild(id, binaryPath: binaryPath) {
        results.append(r)
    }
}

// MARK: - Summary

print("\n\n════════════════════════════════════════════════════════════════════════")
print("Summary — phys_footprint (Activity Monitor \"Memory\" column)")
print("════════════════════════════════════════════════════════════════════════")
print(String(format: "%-34s %10s %10s %10s %8s", "model", "loaded", "peak", "infer Δ", "load"))
print(String(repeating: "─", count: 76))
for r in results {
    print(String(
        format: "%-34s %10s %10s %10s %8s",
        r.modelId.replacingOccurrences(of: "mlx-community/", with: ""),
        fmtGB(r.loaded),
        fmtGB(r.peak),
        fmtMB(r.peak &- r.loaded),
        String(format: "%.1fs", r.loadSec)
    ))
}
print("\nDone.")
