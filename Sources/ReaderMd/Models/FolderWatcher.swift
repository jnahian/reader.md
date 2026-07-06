import Foundation

/// Watches a directory subtree for changes using FSEvents and fires a debounced callback.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let onChange: () -> Void
    private var debounceWork: DispatchWorkItem?

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        start()
    }

    private func start() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.fire()
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func fire() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
