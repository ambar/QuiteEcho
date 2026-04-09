import AppKit
import SwiftUI

// MARK: - Models

struct ModelsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Models")
                        .font(.system(size: 22, weight: .bold))

                    VStack(spacing: 10) {
                        ForEach(Array(AppConfig.modelFamilies.enumerated()), id: \.offset) { _, family in
                            ModelCardView(vm: vm, family: family)
                        }
                    }

                    // Mirror source
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Download Source")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Picker("", selection: Binding(
                            get: { vm.config.useHFMirror },
                            set: { vm.onHFMirrorChange?($0) }
                        )) {
                            Text("Hugging Face (Official)").tag(false)
                            Text("HF Mirror (hf-mirror.com)").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
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
        return family.variants.contains(remembered) ? remembered : family.defaultVariant
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
                    variantPicker
                    variantInfoIcon
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
            ForEach(family.variants, id: \.self) { variant in
                Text(variant).tag(variant)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 80)
        .onTapGesture {} // prevent card tap from firing
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
