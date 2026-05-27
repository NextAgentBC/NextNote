import Foundation

extension URL {
    /// Run `body` with this URL's security-scoped access started; release on
    /// scope exit. Mirrors `defer { stop() }` from a dozen call sites.
    ///
    /// Use when the work is fully synchronous inside the closure. When the
    /// work is async or hops to another actor that needs its own access
    /// window, keep the explicit `let scoped = start...` pattern so the
    /// re-grip lives where it's needed.
    func withSecurityScope<T>(_ body: () throws -> T) rethrows -> T {
        let started = startAccessingSecurityScopedResource()
        defer { if started { stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
