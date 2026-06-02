import Foundation

/// Watches a directory for changes and calls `onChange` (debounced) on the main actor.
/// We watch the directory (not the file) because atomic rename replaces the inode.
@MainActor
final class CacheFileWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var debounceWorkItem: DispatchWorkItem?

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    func start() {
        fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.debouncedFire() }
        }
        src.setCancelHandler { [weak self] in
            MainActor.assumeIsolated {
                if let fd = self?.fd, fd >= 0 { close(fd) }
            }
        }
        source = src
        src.resume()
    }

    private func debouncedFire() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { [weak self] in self?.onChange() }
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
