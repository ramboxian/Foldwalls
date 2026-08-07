import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case checking
        case available
        case downloading
        case extracting
        case installing
        case upToDate
        case failed
    }

    struct Release: Equatable {
        let version: String
        let build: String
        let notes: String
        let size: UInt64
        let publishedAt: Date?
    }

    private enum RequestedAction {
        case none
        case checkOnly
        case install
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: Release?
    @Published private(set) var progress: Double?
    @Published private(set) var receivedBytes: UInt64 = 0
    @Published private(set) var expectedBytes: UInt64 = 0
    @Published private(set) var lastError: String?

    private var updater: SPUUpdater!
    private var requestedAction: RequestedAction = .none
    private var delayedStatusReset: Task<Void, Never>?

    override private init() {
        super.init()

        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )

        do {
            try updater.start()
        } catch {
            phase = .failed
            lastError = error.localizedDescription
        }
    }

    var isUpdateAvailable: Bool {
        release != nil && phase == .available
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .extracting, .installing:
            true
        default:
            false
        }
    }

    var shouldShowToolbarButton: Bool {
        isUpdateAvailable || isBusy
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
    }

    var formattedReleaseSize: String? {
        guard let release, release.size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(release.size), countStyle: .file)
    }

    var statusText: String {
        switch phase {
        case .idle:
            return ""
        case .checking:
            return "Checking for updates…"
        case .available:
            return "Version \(release?.version ?? "") is ready"
        case .downloading:
            if let progress {
                return "Downloading… \(Int(progress * 100))%"
            }
            return "Downloading update…"
        case .extracting:
            return "Preparing update…"
        case .installing:
            return "Installing and restarting…"
        case .upToDate:
            return "You’re up to date"
        case .failed:
            return lastError ?? "Update failed"
        }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        delayedStatusReset?.cancel()
        requestedAction = .checkOnly
        phase = .checking
        lastError = nil
        progress = nil
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard release != nil, !isBusy else { return }
        delayedStatusReset?.cancel()
        requestedAction = .install
        phase = .checking
        lastError = nil
        progress = nil
        receivedBytes = 0
        expectedBytes = release?.size ?? 0
        updater.checkForUpdates()
    }

    private func remember(_ item: SUAppcastItem) {
        let notes = Self.readableNotes(
            item.itemDescription,
            format: item.itemDescriptionFormat
        )
        release = Release(
            version: item.displayVersionString,
            build: item.versionString,
            notes: notes,
            size: item.contentLength,
            publishedAt: item.date
        )
        if expectedBytes == 0 {
            expectedBytes = item.contentLength
        }
    }

    private func resetTransientStatus(after seconds: Double = 4) {
        delayedStatusReset?.cancel()
        delayedStatusReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .upToDate || self.phase == .failed {
                self.phase = .idle
            }
        }
    }

    private static func readableNotes(_ value: String?, format: String? = nil) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "This update includes performance improvements and bug fixes."
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFormat = format?.lowercased()
        if normalizedFormat == "plain-text" || normalizedFormat == "markdown" {
            return trimmed
        }

        let containsHTML = trimmed.range(
            of: #"<([A-Za-z][^>]*)>"#,
            options: .regularExpression
        ) != nil
        guard normalizedFormat == "html" || containsHTML else {
            return trimmed
        }

        if let data = trimmed.data(using: .utf8),
           let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
           ) {
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return trimmed
    }

    // MARK: - SPUUserDriver

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        remember(appcastItem)

        guard !appcastItem.isInformationOnlyUpdate else {
            phase = .available
            requestedAction = .none
            reply(.dismiss)
            return
        }

        if requestedAction == .install {
            phase = state.stage == .installing ? .installing : .downloading
            reply(.install)
        } else {
            phase = .available
            requestedAction = .none
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard var current = release,
              let raw = String(data: downloadData.data, encoding: .utf8) else { return }
        current = Release(
            version: current.version,
            build: current.build,
            notes: Self.readableNotes(raw),
            size: current.size,
            publishedAt: current.publishedAt
        )
        release = current
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // The update itself remains usable even if optional release notes fail.
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        requestedAction = .none
        release = nil
        progress = nil
        phase = .upToDate
        acknowledgement()
        resetTransientStatus()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        requestedAction = .none
        lastError = error.localizedDescription
        progress = nil
        phase = .failed
        acknowledgement()
        resetTransientStatus(after: 7)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        phase = .downloading
        receivedBytes = 0
        progress = expectedBytes > 0 ? 0 : nil
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        progress = expectedContentLength > 0 ? 0 : nil
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        guard expectedBytes > 0 else {
            progress = nil
            return
        }
        progress = min(Double(receivedBytes) / Double(expectedBytes), 1)
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .extracting
        progress = nil
    }

    func showExtractionReceivedProgress(_ extractionProgress: Double) {
        phase = .extracting
        progress = min(max(extractionProgress, 0), 1)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        phase = .installing
        progress = nil
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        phase = .installing
        progress = nil
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        requestedAction = .none
        if release != nil && phase != .failed && phase != .upToDate {
            phase = .available
            progress = nil
        }
    }

    func showUpdateInFocus() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        MainAppWindowController.shared.show()
    }
}
