import AppKit
import SwiftUI

/// The installer only performs an update the coordinator has decided is safe.
@MainActor
@Observable
final class UpdateCoordinator {
    /// One surface for prompt, progress and report: a download cannot move into a dialog.
    enum Stage: Equatable {
        case checking
        case upToDate
        /// A local build has no release stream to compare against, and says so rather than lying.
        case localBuild
        case available(AvailableRelease)
        case blocked(UpdateReadiness.Blocker, AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private(set) var stage: Stage = .checking

    private let store: UpdateCheckStore
    /// Environment injection and activity reads only — never for state this type owns.
    private unowned let core: AppCore
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "Software Update"), contentSize: UpdateWindowView.initialSize,
        activation: core.activationPolicy)
    @ObservationIgnored private var installTask: Task<Void, Never>?

    init(store: UpdateCheckStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    var channel: ReleaseChannel { store.channel }
    var runningVersion: String { store.runningVersion?.description ?? String(localized: "unknown") }

    /// Updates are removed from this fork; the entry points stay as no-ops so the coordinator still compiles.
    func applyEnabled() {}

    func applyAutomaticChecking() {}

    func focusExisting() -> Bool {
        window.focus()
    }

    /// The window takes the height its content measured, so no stage pads itself out with space.
    func fit(height: CGFloat) {
        window.fitContent(width: UpdateWindowView.width, height: height)
    }

    // MARK: - Entry points

    /// The manual action: always opens the window and always asks GitHub.
    func checkForUpdates() {
        guard store.channel.updatesItself else {
            stage = .localBuild
            present()
            return
        }
        if case .installing = stage {
            present()
            return
        }
        stage = .checking
        present()
        Task { [weak self] in
            guard let self else { return }
            let answered = await store.check()
            guard case .checking = stage else { return }
            if let release = store.update {
                stage = .available(release)
            } else if answered {
                stage = .upToDate
            } else {
                stage = .failed(.downloadFailed(String(localized: "Tinycast could not reach GitHub.")))
            }
        }
    }

    /// Updates are removed from this fork; the automatic prompt path is disabled.
    func presentIfAvailable(_ release: AvailableRelease) -> Bool { false }

    // MARK: - Actions

    func install() {
        guard let release = pendingRelease else { return }
        // Re-asked at the moment of the click, never read from a flag that could have gone stale.
        if let blocker = UpdateReadiness.evaluate(core.currentActivity) {
            stage = .blocked(blocker, release)
            return
        }
        stage = .installing(release, .downloading(received: 0, expected: release.assetSize))
        let installer = self.installer
        // Hoisted: nesting the hop inside the task body would re-capture its weak `self`.
        let onProgress: @Sendable (UpdateInstaller.Phase) -> Void = { [weak self] phase in
            Task { @MainActor in self?.report(phase, for: release) }
        }
        installTask = Task { [weak self] in
            do {
                try await installer.install(release, onProgress: onProgress)
                self?.store.recordInstall(of: release.version)
                self?.stage = .readyToRelaunch
            } catch is CancellationError {
                self?.stage = .available(release)
            } catch let failure as UpdateFailure {
                self?.stage = .failed(failure)
            } catch {
                self?.stage = .failed(.downloadFailed(error.localizedDescription))
            }
        }
    }

    /// Dismissing a version is what stops it asking again; a later one still will.
    func skip() {
        if let release = pendingRelease { store.skip(release) }
        window.close()
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    func retry() {
        guard let release = pendingRelease else { return }
        stage = .available(release)
    }

    func dismiss() {
        window.close()
    }

    func relaunch() {
        core.relaunch()
    }

    // MARK: - Private

    private func report(_ phase: UpdateInstaller.Phase, for release: AvailableRelease) {
        guard case .installing = stage else { return }
        stage = .installing(release, phase)
    }

    private var pendingRelease: AvailableRelease? {
        switch stage {
        case .available(let release), .blocked(_, let release), .installing(let release, _):
            return release
        case .checking, .upToDate, .localBuild, .readyToRelaunch, .failed:
            return store.update
        }
    }

    private var installer: UpdateInstaller {
        UpdateInstaller(
            bundleURL: Bundle.main.bundleURL,
            stagingDirectory: AppPaths.caches().appendingPathComponent("Updates", isDirectory: true))
    }

    private func present() {
        window.show {
            UpdateWindowView()
                .environment(self)
        }
    }
}
