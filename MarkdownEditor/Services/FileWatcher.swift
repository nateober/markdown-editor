import Foundation
import CoreServices

/// Watches a directory tree for file system changes using FSEvents.
/// Calls the provided callback (on the main queue) when anything under the
/// watched folder changes. FSEvents is recursive, unlike a kqueue vnode
/// watch, so changes in nested subdirectories are detected too.
final class FileWatcher {

    /// Heap box passed through the C callback context. Retained by the stream
    /// (via the context's release callback) so a callback that is already
    /// enqueued when the watcher is deallocated never dereferences freed
    /// memory — the box outlives the stream, and its closure holds only a
    /// weak reference back to the model via `onChange`'s own captures.
    private final class CallbackBox {
        let onChange: () -> Void
        init(_ onChange: @escaping () -> Void) {
            self.onChange = onChange
        }
    }

    private var stream: FSEventStreamRef?

    init(url: URL, onChange: @escaping () -> Void) {
        startWatching(path: url.path, box: CallbackBox(onChange))
    }

    deinit {
        stopWatching()
    }

    private func startWatching(path: String, box: CallbackBox) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().onChange()
        }

        // WatchRoot: also fire when the watched folder itself is renamed or
        // deleted, so the sidebar can notice its root vanished.
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // latency: coalesce bursts of events
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        ) else {
            // Stream creation failed; release the context info we retained.
            Unmanaged.passUnretained(box).release()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
