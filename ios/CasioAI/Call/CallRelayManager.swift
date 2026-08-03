import CallKit
import Foundation
import Observation

/// Relays system call state to the watch (so it can ring/vibrate and show
/// caller info) and relays the watch's answer/reject button back to the
/// system call.
///
/// Known limitation: CallKit does not expose caller name/number to
/// third-party observers for privacy reasons, so `WatchProtocol.CallEvent`
/// is sent with an empty caller name. The watch can show "Incoming call"
/// generically but not who's calling — flagged for the punch list.
@Observable
final class CallRelayManager: NSObject {
    private let ble: BLEManager
    private let observer = CXCallObserver()
    private let callController = CXCallController()
    private var commandListenerTask: Task<Void, Never>?
    private var currentCallUUID: UUID?

    init(ble: BLEManager) {
        self.ble = ble
        super.init()
        observer.setDelegate(self, queue: .main)
        observeCallCommands()
    }

    private func observeCallCommands() {
        commandListenerTask = Task { [weak self] in
            guard let self else { return }
            for await command in self.ble.callCommandStream() {
                self.handle(command)
            }
        }
    }

    private func handle(_ command: WatchProtocol.CallCommand) {
        guard let uuid = currentCallUUID else { return }
        let action: CXCallAction = command == .answer ? CXAnswerCallAction(call: uuid) : CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { error in
            if let error {
                print("CasioAI: call action failed — \(error.localizedDescription)")
            }
        }
    }
}

extension CallRelayManager: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        currentCallUUID = call.uuid

        let state: WatchProtocol.CallState
        if call.hasEnded {
            state = .idle
        } else if call.hasConnected || call.isOutgoing {
            state = .active
        } else {
            state = .incoming
        }

        ble.sendCallState(WatchProtocol.CallEvent(state: state, callerName: ""))
        ble.setSessionActive(state != .idle)
    }
}
