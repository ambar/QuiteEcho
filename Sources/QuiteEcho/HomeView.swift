import AppKit
import AVFoundation
import SwiftUI

// MARK: - Home

struct HomeView: View {
    @ObservedObject var vm: MainViewModel

    @State private var permTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38)

            if vm.allPermissionsGranted {
                mainContent
            } else {
                permissionsContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).ignoresSafeArea())
        .onAppear {
            vm.refreshPermissions()
            startPermPollingIfNeeded()
        }
        .onDisappear { stopPermPolling() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshPermissions()
        }
        .onChange(of: vm.allPermissionsGranted) {
            if vm.allPermissionsGranted { stopPermPolling() }
        }
    }

    private func startPermPollingIfNeeded() {
        guard !vm.allPermissionsGranted else { return }
        stopPermPolling()
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak vm] _ in
            guard let vm else { return }
            DispatchQueue.main.async { vm.refreshPermissions() }
        }
    }

    private func stopPermPolling() {
        permTimer?.invalidate()
        permTimer = nil
    }

    // MARK: Main content (permissions granted)

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    usageGrid
                    hotkeyHint
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            Divider()

            statusLine
                .padding(.vertical, 10)
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("QuiteEcho")
                    .font(.system(size: 18, weight: .bold))
                Text("Fast, private, offline speech-to-text. Stay in your flow.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: Permissions (not granted)

    private var permissionsContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions Required")
                        .font(.system(size: 20, weight: .bold))
                    Text("QuiteEcho needs the following permissions to work.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    permissionRow(
                        name: "Microphone",
                        description: "Record audio for speech recognition",
                        granted: vm.permMicrophone,
                        action: requestMicrophone
                    )
                    permissionRow(
                        name: "Accessibility",
                        description: "Global hotkey and paste into apps",
                        granted: vm.permAccessibility,
                        action: requestAccessibility
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

                Button(action: { vm.refreshPermissions() }) {
                    Text("Refresh Status")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func permissionRow(
        name: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(granted ? .green : Color(nsColor: .tertiaryLabelColor))
                        .font(.system(size: 15))
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 21)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { vm.refreshPermissions() }
        }
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        // Poll for a few seconds since macOS doesn't callback
        for delay in [1.0, 2.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                vm.refreshPermissions()
            }
        }
    }

    // MARK: Usage grid

    private var usageGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Usage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                statCard(vm.stats.formattedTime, "Dictation", icon: "mic.fill", color: .blue)
                statCard("\(vm.stats.wordsDictated)", "Words", icon: "text.word.spacing", color: .purple)
                statCard("\(vm.stats.sessionsCount)", "Sessions", icon: "repeat", color: .orange)
                statCard(vm.stats.timeSaved, "Time saved", icon: "clock.arrow.circlepath", color: .green)
                statCard("\(vm.stats.avgWPM)", "Avg WPM", icon: "gauge.with.dots.needle.33percent", color: .pink)
            }
        }
    }

    private func statCard(_ value: String, _ label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: Hotkey hint

    private var hotkeyHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Press \(vm.config.hotkeyDisplayString) to start dictating")
                    .font(.system(size: 13, weight: .medium))
                Text(vm.config.hotkeyMode == "hold" ? "Hold to record" : "Toggle on/off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { vm.selectedTab = .settings }) {
                Text("Change")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: Status (bottom center)

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.quaternary)
            Text(vm.config.modelLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        if vm.isRecording { return .red }
        switch vm.asrState {
        case .ready:        return .green
        case .downloading:  return .blue
        case .loading:      return .orange
        case .error:        return .red
        case .idle:         return .gray
        }
    }

    private var statusText: String {
        if vm.isRecording { return "Recording" }
        switch vm.asrState {
        case .ready:              return "Ready"
        case .downloading(let p): return "Downloading \(Int(p))%"
        case .loading:            return "Loading"
        case .error(let m):       return m
        case .idle:               return "Idle"
        }
    }
}
