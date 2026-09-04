import Foundation

/// Watches one file and says when something else writes to it.
///
/// It re-arms after every event on purpose. Present saves with `.atomic`, and
/// so do most editors: the new contents land in a temporary file that then
/// replaces the original, which leaves the descriptor we were watching pointing
/// at an inode nobody can reach any more. One event is all a stale descriptor
/// ever reports. Watching the containing folder instead — the usual way round
/// this — is not open to us under the sandbox, where the grant covers the file
/// the user picked and nothing else.
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var url: URL?
    private var onChange: (() -> Void)?
    private var pending: Task<Void, Never>?

    /// Editors write in bursts — truncate, write, rename — and every step is an
    /// event. Let the dust settle before anybody reads the file.
    private static let settleTime = Duration.milliseconds(250)

    /// Starts over on `url`, dropping whatever was being watched before.
    func watch(_ url: URL, onChange: @escaping () -> Void) {
        stop()
        self.url = url
        self.onChange = onChange
        arm()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        url = nil
        onChange = nil
    }

    private func arm() {
        guard let url else { return }
        // O_EVTONLY: opened to be told about, not to read from.
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // The source was made on the main queue, so this is the main actor.
            MainActor.assumeIsolated { self?.fileEvent() }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func fileEvent() {
        // Whatever we are holding may now be a replaced inode. Let it go and
        // start again from the path once the writer has finished.
        source?.cancel()
        source = nil
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: FileWatcher.settleTime)
            guard !Task.isCancelled, let self else { return }
            self.arm()
            self.onChange?()
        }
    }
}
