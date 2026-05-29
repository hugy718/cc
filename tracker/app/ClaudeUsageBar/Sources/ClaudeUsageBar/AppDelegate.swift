import AppKit
import Combine
import SwiftUI
import ClaudeUsageBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings()
    private var viewModel: UsageViewModel!
    private var reader: CacheFileReader!
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var watcher: CacheFileWatcher?
    private var popover: NSPopover!

    private var cacheURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/usage-cache.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let formatter = ResetFormatter(clock: settings.clock, calendar: .current)
        viewModel = UsageViewModel(formatter: formatter,
                                   evaluator: SnapshotEvaluator(staleAfter: 1800))
        reader = CacheFileReader(url: cacheURL)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        viewModel.$menuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.statusItem.button?.title = text }
            .store(in: &cancellables)

        refresh()
        startTimer()

        watcher = CacheFileWatcher(directoryURL: cacheURL.deletingLastPathComponent()) { [weak self] in
            self?.refresh()
        }
        watcher?.start()

        let content = DropdownView(
            viewModel: viewModel,
            resetText: { [weak self] date in
                let clock = self?.settings.clock ?? .twentyFourHour
                return ResetFormatter(clock: clock, calendar: .current).string(for: date, now: Date())
            },
            onRefresh: { [weak self] in self?.refresh() },
            onQuit: { NSApp.terminate(nil) })
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: content)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshInterval),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let snapshot = reader.read()
        viewModel.apply(snapshot: snapshot, now: Date())
    }
}
