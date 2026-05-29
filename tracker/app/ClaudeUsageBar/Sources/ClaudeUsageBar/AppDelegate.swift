import AppKit
import Combine
import ClaudeUsageBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings()
    private var viewModel: UsageViewModel!
    private var reader: CacheFileReader!
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

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
