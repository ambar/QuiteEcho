import AppKit
import Sparkle

// MARK: - Update State

enum UpdateState: Equatable {
    case idle
    case checking
    case available(version: String, notes: String?)
    case downloading(version: String, progress: Double)
    case extracting(version: String, progress: Double)
    case readyToInstall(version: String)
    case installing(version: String)
    case notFound
    case error(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var version: String? {
        switch self {
        case .available(let v, _),
             .downloading(let v, _),
             .extracting(let v, _),
             .readyToInstall(let v),
             .installing(let v):
            return v
        default:
            return nil
        }
    }
}

// MARK: - Custom User Driver

/// Replaces Sparkle's standard modal UI with ViewModel-driven state shown in a popover.
final class PopoverUpdateDriver: NSObject, SPUUserDriver {
    var onStateChange: ((UpdateState) -> Void)?

    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var downloadCancellation: (() -> Void)?
    private var checkCancellation: (() -> Void)?
    private var expectedContentLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0
    private var lastFoundVersion: String = ""

    // MARK: - User actions

    func userDidChooseInstall() {
        updateReply?(.install)
        updateReply = nil
    }

    func userDidChooseDismiss() {
        updateReply?(.dismiss)
        updateReply = nil
    }

    func userDidChooseSkip() {
        updateReply?(.skip)
        updateReply = nil
    }

    func userDidChooseInstallAndRelaunch() {
        installReply?(.install)
        installReply = nil
    }

    func userDidCancelDownload() {
        downloadCancellation?()
        downloadCancellation = nil
    }

    // MARK: - SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        onStateChange?(.checking)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateReply = reply
        lastFoundVersion = appcastItem.displayVersionString
        onStateChange?(.available(version: appcastItem.displayVersionString, notes: appcastItem.itemDescription))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    @MainActor
    func showUpdateNotFoundWithError(_ error: any Error) async {
        onStateChange?(.notFound)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        onStateChange?(.idle)
    }

    @MainActor
    func showUpdaterError(_ error: any Error) async {
        onStateChange?(.error(error.localizedDescription))
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        onStateChange?(.idle)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellation = cancellation
        expectedContentLength = 0
        downloadedLength = 0
        onStateChange?(.downloading(version: lastFoundVersion, progress: 0))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength += length
        let progress = expectedContentLength > 0 ? Double(downloadedLength) / Double(expectedContentLength) : 0
        onStateChange?(.downloading(version: lastFoundVersion, progress: min(progress, 1.0)))
    }

    func showDownloadDidStartExtractingUpdate() {
        onStateChange?(.extracting(version: lastFoundVersion, progress: 0))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        onStateChange?(.extracting(version: lastFoundVersion, progress: progress))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        onStateChange?(.readyToInstall(version: lastFoundVersion))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        onStateChange?(.installing(version: lastFoundVersion))
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        onStateChange?(.idle)
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        updateReply = nil
        installReply = nil
        downloadCancellation = nil
        checkCancellation = nil
        onStateChange?(.idle)
    }
}
