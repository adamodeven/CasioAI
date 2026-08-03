import Foundation

/// Fan-out helper: a plain `AsyncStream` only delivers each element to
/// whichever single consumer happens to be awaiting `next()` — if two
/// listeners both iterate the same stream, events get split between them at
/// random instead of both seeing everything. Several parts of this app
/// (voice turns and thought capture) independently listen for the same
/// watch button events, so producers use this to hand every subscriber its
/// own stream that receives every broadcast element.
final class EventBroadcaster<Element> {
    private var subscribers: [UUID: AsyncStream<Element>.Continuation] = [:]
    private let lock = NSLock()

    func subscribe() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func broadcast(_ element: Element) {
        lock.lock()
        let continuations = Array(subscribers.values)
        lock.unlock()
        for continuation in continuations {
            continuation.yield(element)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        subscribers[id] = nil
        lock.unlock()
    }
}
