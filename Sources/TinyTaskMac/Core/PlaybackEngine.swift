import AppKit
import ApplicationServices
import Foundation

enum PlaybackEngineError: Error, LocalizedError {
    case alreadyRunning
    case failedToCreateEvent(MacroEventKind)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Playback is already running."
        case let .failedToCreateEvent(kind):
            return "Failed to synthesize \(kind)."
        }
    }
}

final class PlaybackEngine: @unchecked Sendable {
    private let stateLock = NSLock()

    private var workerThread: Thread?
    private var stopRequested = false

    let syntheticMarker: Int64

    init(syntheticMarker: Int64) {
        self.syntheticMarker = syntheticMarker
    }

    func start(document: MacroDocument, completion: @escaping @Sendable @MainActor (Result<Void, Error>) -> Void) throws {
        stateLock.lock()
        guard workerThread == nil else {
            stateLock.unlock()
            throw PlaybackEngineError.alreadyRunning
        }
        stopRequested = false
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.runPlayback(document: document, completion: completion)
        }
        thread.name = "TinyTaskMac.Playback"
        thread.qualityOfService = .userInteractive

        stateLock.lock()
        workerThread = thread
        stateLock.unlock()
        thread.start()
    }

    func stop() {
        stateLock.lock()
        stopRequested = true
        stateLock.unlock()
    }

    private func runPlayback(document: MacroDocument, completion: @escaping @Sendable @MainActor (Result<Void, Error>) -> Void) {
        defer {
            stateLock.lock()
            workerThread = nil
            stopRequested = false
            stateLock.unlock()
        }

        do {
            let source = CGEventSource(stateID: .hidSystemState)
            let speed = document.settings.playbackMode == .scaled ? max(0.1, document.settings.playbackSpeedMultiplier) : 1.0

            playbackLoop: while !shouldStop() {
                let playbackStart = DispatchTime.now().uptimeNanoseconds
                var deadline = playbackStart

                for record in document.events {
                    if shouldStop() {
                        break playbackLoop
                    }

                    let scaledDelta = UInt64(Double(record.deltaNanos) / speed)
                    deadline += scaledDelta
                    wait(until: deadline)

                    try post(record, source: source)
                }

                if document.settings.repeatMode == .once {
                    break playbackLoop
                }
            }

            Task { @MainActor in
                completion(.success(()))
            }
        } catch {
            Task { @MainActor in
                completion(.failure(error))
            }
        }
    }

    private func shouldStop() -> Bool {
        stateLock.withLock { stopRequested }
    }

    private func wait(until deadline: UInt64) {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline || shouldStop() {
                return
            }

            let remaining = deadline - now
            if remaining > 2_000_000 {
                Thread.sleep(forTimeInterval: Double(remaining - 1_000_000) / 1_000_000_000.0)
            }
        }
    }

    private func post(_ record: MacroEventRecord, source: CGEventSource?) throws {
        let event = try makeEvent(from: record, source: source)
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private func makeEvent(from record: MacroEventRecord, source: CGEventSource?) throws -> CGEvent {
        switch record.kind {
        case .mouseMove, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: record.kind.cgEventType,
                mouseCursorPosition: CGPoint(x: record.x, y: record.y),
                mouseButton: mouseButton(for: record.kind, buttonNumber: record.buttonNumber)
            ) else {
                throw PlaybackEngineError.failedToCreateEvent(record.kind)
            }

            event.flags = CGEventFlags(rawValue: record.modifierFlagsRaw)
            event.setIntegerValueField(.mouseEventClickState, value: Int64(record.clickCount))
            return event

        case .scroll:
            let unit: CGScrollEventUnit = record.scrollUnit == 1 ? .pixel : .line
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: unit,
                wheelCount: 2,
                wheel1: record.scrollY,
                wheel2: record.scrollX,
                wheel3: 0
            ) else {
                throw PlaybackEngineError.failedToCreateEvent(record.kind)
            }

            event.flags = CGEventFlags(rawValue: record.modifierFlagsRaw)
            return event

        case .keyDown:
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(record.keyCode), keyDown: true) else {
                throw PlaybackEngineError.failedToCreateEvent(record.kind)
            }
            event.flags = CGEventFlags(rawValue: record.modifierFlagsRaw)
            return event

        case .keyUp:
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(record.keyCode), keyDown: false) else {
                throw PlaybackEngineError.failedToCreateEvent(record.kind)
            }
            event.flags = CGEventFlags(rawValue: record.modifierFlagsRaw)
            return event

        case .flagsChanged:
            let isDown = modifierStateForFlagsChanged(keyCode: record.keyCode, flags: record.modifierFlagsRaw)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(record.keyCode), keyDown: isDown) else {
                throw PlaybackEngineError.failedToCreateEvent(record.kind)
            }
            event.flags = CGEventFlags(rawValue: record.modifierFlagsRaw)
            return event
        }
    }

    private func mouseButton(for kind: MacroEventKind, buttonNumber: UInt8) -> CGMouseButton {
        switch kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return .right
        default:
            return CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
        }
    }

    private func modifierStateForFlagsChanged(keyCode: UInt16, flags: UInt64) -> Bool {
        let cgFlags = CGEventFlags(rawValue: flags)
        switch keyCode {
        case 54, 55:
            return cgFlags.contains(.maskCommand)
        case 56, 60:
            return cgFlags.contains(.maskShift)
        case 58, 61:
            return cgFlags.contains(.maskAlternate)
        case 59, 62:
            return cgFlags.contains(.maskControl)
        case 57:
            return cgFlags.contains(.maskAlphaShift)
        default:
            return true
        }
    }
}
