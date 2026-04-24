import Foundation

// Per-folder debounce for dashboard regeneration triggers. When a note is
// saved, its parent folder is marked dirty; a timer fires after `debounce`
// seconds of quiet and runs the regen. Multiple dirty folders fire
// independently (two saves in different topics each schedule their own
// regen — no global single-timer shared fate).
actor DirtyTracker {
    private var tasks: [String: Task<Void, Never>] = [:]
    private let debounce: TimeInterval

    init(debounce: TimeInterval = 30) {
        self.debounce = debounce
    }

    /// Schedule regen for `folder` after `debounce` seconds. Successive
    /// calls for the same folder cancel and reschedule.
    func markDirty(folder: String, run: @escaping @Sendable (String) async -> Void) {
        tasks[folder]?.cancel()
        let secs = debounce
        tasks[folder] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await run(folder)
            await self?.clear(folder: folder)
        }
    }

    func cancelAll() {
        for t in tasks.values { t.cancel() }
        tasks.removeAll()
    }

    private func clear(folder: String) {
        tasks.removeValue(forKey: folder)
    }
}
