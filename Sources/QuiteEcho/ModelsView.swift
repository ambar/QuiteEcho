import AppKit
import SwiftUI

// MARK: - Models

struct ModelsView: View {
    @ObservedObject var vm: MainViewModel
    @State private var showBenchmarks: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Models")
                            .font(.system(size: 22, weight: .bold))
                        Spacer()
                        benchmarksButton
                        downloadSourcePicker
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(AppConfig.modelFamilies.enumerated()), id: \.offset) { _, family in
                            ModelCardView(vm: vm, family: family)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
    }

    private var benchmarksButton: some View {
        Button {
            showBenchmarks.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 11))
                Text("Benchmarks")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Compare published accuracy across model families")
        .popover(isPresented: $showBenchmarks, arrowEdge: .top) {
            benchmarksPopover
        }
    }

    @ViewBuilder
    private var benchmarksPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Benchmarks")
                .font(.system(size: 13, weight: .semibold))
            Text("Published accuracy on standard ASR benchmarks (lower WER is better)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(Self.benchmarkRows, id: \.family) { row in
                    GridRow {
                        Text(row.family)
                            .font(.system(size: 12, weight: .medium))
                        Text(row.metric)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(row.bestFor)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Text("Numbers are from upstream papers / HF model cards on bf16/fp16 weights. MLX quantization may add 0.1–0.5 pp WER. Benchmarks use different datasets — don't compare rows directly.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 560)
    }

    private struct BenchmarkRow {
        let family: String
        let metric: String
        let bestFor: String
    }

    private static let benchmarkRows: [BenchmarkRow] = [
        .init(family: "Qwen3-ASR-0.6B", metric: "LibriSpeech 2.11 / 4.55", bestFor: "Multilingual, light"),
        .init(family: "Qwen3-ASR-1.7B", metric: "FLEURS en 3.35 / zh 2.41", bestFor: "Multilingual + Chinese"),
        .init(family: "Parakeet-TDT-0.6B", metric: "OpenASR 6.32, RTFx 3330", bestFor: "English, fastest"),
        .init(family: "Parakeet-TDT-1.1B", metric: "OpenASR 5.63, LibriSpeech 1.6 / 3.1", bestFor: "English, larger"),
        .init(family: "Voxtral-Mini-4B-Realtime", metric: "FLEURS top-10 ~4%", bestFor: "Streaming, low latency"),
        .init(family: "GLM-ASR-Nano", metric: "Aishell-1 CER 0.07", bestFor: "Chinese + Cantonese"),
        .init(family: "Granite-Speech-1B", metric: "OpenASR 5.52", bestFor: "English + translation"),
        .init(family: "Cohere-Transcribe-03-2026", metric: "OpenASR 5.42 (#1)", bestFor: "English SOTA, 14 langs"),
    ]

    private var downloadSourcePicker: some View {
        Menu {
            Button {
                vm.onHFMirrorChange?(false)
            } label: {
                if !vm.config.useHFMirror {
                    Label("Hugging Face (Official)", systemImage: "checkmark")
                } else {
                    Text("Hugging Face (Official)")
                }
            }
            Button {
                vm.onHFMirrorChange?(true)
            } label: {
                if vm.config.useHFMirror {
                    Label("HF Mirror (hf-mirror.com)", systemImage: "checkmark")
                } else {
                    Text("HF Mirror (hf-mirror.com)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                Text(vm.config.useHFMirror ? "HF Mirror" : "Hugging Face")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Download source for model files")
    }
}

struct ModelCardView: View {
    @ObservedObject var vm: MainViewModel
    let family: AppConfig.ModelFamily
    @State private var dirSize: Int64 = 0
    @State private var sizeTimer: Timer?
    @State private var showVariantInfo: Bool = false

    private var currentModelId: String {
        family.modelId(selectedVariant)
    }

    private var selectedVariant: String {
        let remembered = family.variant(of: vm.config.model) ?? vm.config.variant(for: family)
        // Fall back to default if the remembered variant is no longer offered
        // (e.g. a config written before 5bit was removed from the variant list).
        return family.variants.contains(where: { $0.name == remembered }) ? remembered : family.defaultVariant
    }

    private var selected: Bool { family.hasVariant(vm.config.model) }
    private var isLoading: Bool {
        guard selected else { return false }
        switch vm.asrState {
        case .loading, .downloading: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text(family.name)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    Text(family.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    modelStateBadge
                }

                HStack(spacing: 4) {
                    if family.variants.count > 1 {
                        variantPicker
                    } else if Self.isQuantizationLabel(selectedVariant) {
                        variantChip
                    }
                    if family.kind == .qwen3ASR {
                        variantInfoIcon
                    }
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.onModelChange?(currentModelId)
            }

            Divider().padding(.horizontal, 12)

            if selected, case .downloading(let pct) = vm.asrState {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("Downloading… \(Int(pct))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if dirSize > 0 {
                            Text(formatBytes(dirSize))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ProgressView(value: pct, total: 100)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if let path = modelCachePath(currentModelId) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(abbreviatePath(path))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if dirSize > 0 {
                        Text(formatBytes(dirSize))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Downloaded on first use")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    selected ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
        .onAppear { refreshSize(); updateTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: vm.asrState) { updateTimer() }
        .onChange(of: vm.config.model) { refreshSize() }
    }

    // MARK: - Variant picker

    private var variantInfoIcon: some View {
        Button {
            showVariantInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show memory requirements")
        .popover(isPresented: $showVariantInfo, arrowEdge: .top) {
            variantInfoPopover
        }
    }

    @ViewBuilder
    private var variantInfoPopover: some View {
        let is17B = family.name.contains("1.7B")
        // (variant, peak GB, note)
        let rows: [(String, Double, String)] = is17B
            ? [
                ("bf16", 5.0, "full precision"),
                ("8bit", 3.4, "default"),
                ("6bit", 3.0, "smaller"),
                ("4bit", 2.6, "smallest"),
              ]
            : [
                ("bf16", 2.4, "full precision"),
                ("8bit", 1.9, "default"),
                ("6bit", 1.7, "smaller"),
                ("4bit", 1.6, "smallest"),
              ]

        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(family.name) — peak memory")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Your Mac: \(String(format: "%.0f", totalGB)) GB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Peak = model weights + inference activations")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { variant, peakGB, note in
                    HStack(spacing: 8) {
                        memoryFitIcon(peakGB: peakGB, totalGB: totalGB)
                            .frame(width: 14)
                        Text(variant)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 42, alignment: .leading)
                        Text("~\(String(format: "%.1f", peakGB)) GB")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        if !note.isEmpty {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text("comfortable")
                }
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("ok")
                }
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("tight")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder
    private func memoryFitIcon(peakGB: Double, totalGB: Double) -> some View {
        // ✓ comfortable: peak <= 50% RAM
        // ✓ (outlined) ok: 50% – 65%
        // ⚠️ tight:  peak > 65% RAM
        let ratio = peakGB / totalGB
        if ratio <= 0.5 {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        } else if ratio > 0.65 {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var variantPicker: some View {
        Picker("", selection: Binding(
            get: { selectedVariant },
            set: { newVariant in
                vm.onModelChange?(family.modelId(newVariant))
            }
        )) {
            ForEach(family.variants, id: \.name) { variant in
                Text(variant.name).tag(variant.name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 90)
        .onTapGesture {} // prevent card tap from firing
    }

    /// Variant labels that represent a quantization / precision level and
    /// are therefore useful to surface in the chip. Version or architecture
    /// tags like "v3" or "tdt" add no actionable info — they're hidden.
    static func isQuantizationLabel(_ name: String) -> Bool {
        ["4bit", "5bit", "6bit", "8bit", "bf16", "fp16"].contains(name)
    }

    /// For families with only one variant the picker is useless — render a
    /// static chip showing the variant name so the row still has a visual
    /// anchor in the same column as the multi-variant pickers.
    private var variantChip: some View {
        Text(selectedVariant)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: .separatorColor).opacity(0.3))
            .clipShape(Capsule())
    }

    // MARK: - State badge

    @ViewBuilder
    private var modelStateBadge: some View {
        switch vm.asrState {
        case .loading, .downloading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Loading")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: .separatorColor).opacity(0.3))
            .clipShape(Capsule())
        case .ready:
            Text("Ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
        case .error:
            Text("Error")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
        default:
            Text("Active")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    // MARK: - Size polling

    private func updateTimer() {
        if isLoading {
            guard sizeTimer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refreshSize()
            }
            sizeTimer = timer
        } else {
            stopTimer()
            refreshSize()
        }
    }

    private func stopTimer() {
        sizeTimer?.invalidate()
        sizeTimer = nil
    }

    private func refreshSize() {
        let id = currentModelId
        DispatchQueue.global(qos: .utility).async {
            let size = Self.directorySize(for: id)
            DispatchQueue.main.async { dirSize = size }
        }
    }

    // MARK: - Helpers

    private static func directorySize(for modelId: String) -> Int64 {
        let path = AppConfig.modelCacheDir(modelId)
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let full = (path as NSString).appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: full),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    private func modelCachePath(_ modelId: String) -> String? {
        let path = AppConfig.modelCacheDir(modelId)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
