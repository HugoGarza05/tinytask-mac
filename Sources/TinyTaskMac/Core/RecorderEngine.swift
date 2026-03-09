import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

enum RecorderEngineError: Error, LocalizedError {
    case couldNotStartTap
    case recordingNotActive
    case spoolFailure

    var errorDescription: String? {
        switch self {
        case .couldNotStartTap:
            return "TinyTaskMac could not start the global input monitor."
        case .recordingNotActive:
            return "Recording is not active."
        case .spoolFailure:
            return "TinyTaskMac could not finalize the captured event stream."
        }
    }
}

final class RecorderEngine: @unchecked Sendable {
    private enum Mode {
        case idle
        case recording
        case playbackMonitoring
    }

    private let stateLock = NSLock()
    private let tapReadySemaphore = DispatchSemaphore(value: 0)

    private var mode: Mode = .idle
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var tapStartAttempted = false
    private var tapStartedSuccessfully = false
    private var spoolWriter: EventSpoolWriter?
    private var lastTimestamp: UInt64 = 0
    private var hotKeys: [HotKeyDescriptor] = []
    private var suppressionDeadline: UInt64 = 0
    private var lastHumanInputNotice: UInt64 = 0

    let syntheticMarker: Int64 = 0x544D_4D41_43

    var onHumanInputDuringPlayback: (@MainActor () -> Void)?
    var onTapFailure: (@MainActor (String) -> Void)?

    deinit {
        stopMonitoring()
    }

    func ensureMonitoringStarted() -> Bool {
        stateLock.lock()
        if tapStartedSuccessfully {
            stateLock.unlock()
            return true
        }

        if tapStartAttempted {
            stateLock.unlock()
            return false
        }

        tapStartAttempted = true
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.runTapThread()
        }
        thread.name = "TinyTaskMac.InputTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        tapReadySemaphore.wait()

        stateLock.lock()
        let started = tapStartedSuccessfully
        stateLock.unlock()
        return started
    }

    func startRecording(filteredHotKeys: [HotKeyDescriptor]) throws {
        guard ensureMonitoringStarted() else {
            throw RecorderEngineError.couldNotStartTap
        }

        let writer = try EventSpoolWriter()
        stateLock.lock()
        mode = .recording
        hotKeys = filteredHotKeys
        spoolWriter = writer
        lastTimestamp = 0
        suppressionDeadline = 0
        stateLock.unlock()
    }

    func stopRecording() throws -> [MacroEventRecord] {
        let writer: EventSpoolWriter?
        stateLock.lock()
        guard case .recording = mode else {
            stateLock.unlock()
            throw RecorderEngineError.recordingNotActive
        }

        mode = .idle
        writer = spoolWriter
        spoolWriter = nil
        hotKeys = []
        lastTimestamp = 0
        stateLock.unlock()

        guard let writer else {
            throw RecorderEngineError.spoolFailure
        }

        let url = try writer.finish()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        return try EventSpoolWriter.decodeRecords(from: data)
    }

    func beginPlaybackMonitoring() {
        _ = ensureMonitoringStarted()
        stateLock.lock()
        mode = .playbackMonitoring
        lastHumanInputNotice = 0
        stateLock.unlock()
    }

    func endPlaybackMonitoring() {
        stateLock.lock()
        if case .playbackMonitoring = mode {
            mode = .idle
        }
        stateLock.unlock()
    }

    func noteControlHotKeyTriggered() {
        stateLock.lock()
        suppressionDeadline = DispatchTime.now().uptimeNanoseconds + 300_000_000
        stateLock.unlock()
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }

        if let eventSource {
            CFRunLoopSourceInvalidate(eventSource)
        }

        if let tapRunLoop {
            CFRunLoopPerformBlock(tapRunLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(tapRunLoop)
            }
            CFRunLoopWakeUp(tapRunLoop)
        }
    }

    private func runTapThread() {
        let mask = Self.eventMask
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let engine = Unmanaged<RecorderEngine>.fromOpaque(userInfo).takeUnretainedValue()
            return engine.handleTap(type: type, event: event)
        }

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        stateLock.lock()
        eventTap = tap
        tapStartedSuccessfully = tap != nil
        stateLock.unlock()
        tapReadySemaphore.signal()

        guard let tap else {
            let handler = stateLock.withLock { onTapFailure }
            Task { @MainActor in
                handler?("Failed to start the input monitor. Check Input Monitoring permission.")
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        stateLock.lock()
        eventSource = source
        stateLock.unlock()

        if let source {
            let runLoop = CFRunLoopGetCurrent()
            stateLock.lock()
            tapRunLoop = runLoop
            stateLock.unlock()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        guard let kind = MacroEventKind(eventType: type) else {
            return Unmanaged.passUnretained(event)
        }

        let now = DispatchTime.now().uptimeNanoseconds

        stateLock.lock()
        let currentMode = mode
        let suppressed = now < suppressionDeadline
        let hotKeys = hotKeys
        let writer = spoolWriter
        let lastNotice = lastHumanInputNotice
        stateLock.unlock()

        switch currentMode {
        case .idle:
            break
        case .recording:
            if suppressed || Self.matchesAnyHotKey(event: event, hotKeys: hotKeys) {
                return Unmanaged.passUnretained(event)
            }

            let delta = stateLock.withLock {
                defer { lastTimestamp = now }
                let previous = lastTimestamp
                return previous == 0 ? 0 : now - previous
            }

            if let record = Self.makeRecord(from: event, kind: kind, deltaNanos: delta) {
                writer?.append(record)
            }
        case .playbackMonitoring:
            if now - lastNotice > 250_000_000 {
                stateLock.lock()
                lastHumanInputNotice = now
                stateLock.unlock()
                let handler = stateLock.withLock { onHumanInputDuringPlayback }
                Task { @MainActor in
                    handler?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private static func makeRecord(from event: CGEvent, kind: MacroEventKind, deltaNanos: UInt64) -> MacroEventRecord? {
        let location = event.location
        let displayID = DisplayLayout.displayID(containing: location)
        let flagsRaw = event.flags.rawValue

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let buttonNumber = UInt8(max(0, event.getIntegerValueField(.mouseEventButtonNumber)))
        let clickCount = UInt8(max(0, event.getIntegerValueField(.mouseEventClickState)))

        let pointScrollX = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let pointScrollY = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let lineScrollX = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let lineScrollY = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))

        let usePointUnits = pointScrollX != 0 || pointScrollY != 0
        let scrollX = usePointUnits ? pointScrollX : lineScrollX
        let scrollY = usePointUnits ? pointScrollY : lineScrollY

        return MacroEventRecord(
            kind: kind,
            flagsRaw: flagsRaw,
            deltaNanos: deltaNanos,
            x: kind.isMouseEvent || kind == .scroll ? location.x : 0,
            y: kind.isMouseEvent || kind == .scroll ? location.y : 0,
            keyCode: keyCode,
            buttonNumber: buttonNumber,
            clickCount: clickCount,
            scrollX: scrollX,
            scrollY: scrollY,
            scrollUnit: usePointUnits ? 1 : 0,
            displayID: displayID,
            modifierFlagsRaw: flagsRaw
        )
    }

    private static func matchesAnyHotKey(event: CGEvent, hotKeys: [HotKeyDescriptor]) -> Bool {
        let eventKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = carbonFlags(from: event.flags)

        return hotKeys.contains { descriptor in
            descriptor.keyCode == eventKeyCode && descriptor.carbonModifiers == flags
        }
    }

    private static func carbonFlags(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0

        if flags.contains(.maskControl) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.maskAlternate) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.maskShift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.maskCommand) {
            result |= UInt32(cmdKey)
        }

        return result
    }

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel, .keyDown, .keyUp, .flagsChanged
        ]

        return types.reduce(0) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }()
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class EventSpoolWriter: @unchecked Sendable {
    private let fileURL: URL
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private let flushSemaphore = DispatchSemaphore(value: 0)
    private let finishedSemaphore = DispatchSemaphore(value: 0)
    private let writerQueue = DispatchQueue(label: "TinyTaskMac.EventSpoolWriter", qos: .userInitiated)

    private var pending = Data()
    private var shouldFinish = false

    init() throws {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("TinyTaskMac-\(UUID().uuidString).events")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)

        writerQueue.async { [weak self] in
            self?.writerLoop()
        }
    }

    func append(_ record: MacroEventRecord) {
        let encoded = Self.encode(record)
        lock.lock()
        pending.append(encoded)
        let shouldFlush = pending.count >= 64 * 1024
        lock.unlock()

        if shouldFlush {
            flushSemaphore.signal()
        }
    }

    func finish() throws -> URL {
        lock.lock()
        shouldFinish = true
        lock.unlock()
        flushSemaphore.signal()
        finishedSemaphore.wait()
        try fileHandle.synchronize()
        try fileHandle.close()
        return fileURL
    }

    private func writerLoop() {
        while true {
            flushSemaphore.wait()

            let chunk: Data = lock.withLock {
                let bytes = pending
                pending.removeAll(keepingCapacity: true)
                return bytes
            }

            if !chunk.isEmpty {
                try? fileHandle.write(contentsOf: chunk)
            }

            let done = lock.withLock { shouldFinish && pending.isEmpty }
            if done {
                finishedSemaphore.signal()
                return
            }
        }
    }

    static func decodeRecords(from data: Data) throws -> [MacroEventRecord] {
        var reader = EventReader(data: data)
        var result: [MacroEventRecord] = []

        while !reader.isAtEnd {
            result.append(try reader.readRecord())
        }

        return result
    }

    private static func encode(_ record: MacroEventRecord) -> Data {
        var data = Data(capacity: 64)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendDouble(_ value: Double) {
            append(value.bitPattern)
        }

        append(record.kind.rawValue)
        append(UInt8(0))
        append(UInt16(0))
        append(record.flagsRaw)
        append(record.deltaNanos)
        appendDouble(record.x)
        appendDouble(record.y)
        append(record.keyCode)
        append(record.buttonNumber)
        append(record.clickCount)
        append(record.scrollX)
        append(record.scrollY)
        append(record.scrollUnit)
        append(UInt8(0))
        append(UInt16(0))
        append(record.displayID)
        append(record.modifierFlagsRaw)
        return data
    }
}

private struct EventReader {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readRecord() throws -> MacroEventRecord {
        guard offset + 57 <= data.count else {
            throw RecorderEngineError.spoolFailure
        }

        guard let kind = MacroEventKind(rawValue: read(UInt8.self)) else {
            throw RecorderEngineError.spoolFailure
        }
        _ = read(UInt8.self)
        _ = read(UInt16.self)

        let flagsRaw = read(UInt64.self)
        let deltaNanos = read(UInt64.self)
        let x = Double(bitPattern: read(UInt64.self))
        let y = Double(bitPattern: read(UInt64.self))
        let keyCode = read(UInt16.self)
        let buttonNumber = read(UInt8.self)
        let clickCount = read(UInt8.self)
        let scrollX = read(Int32.self)
        let scrollY = read(Int32.self)
        let scrollUnit = read(UInt8.self)
        _ = read(UInt8.self)
        _ = read(UInt16.self)
        let displayID = read(UInt32.self)
        let modifierFlagsRaw = read(UInt64.self)

        return MacroEventRecord(
            kind: kind,
            flagsRaw: flagsRaw,
            deltaNanos: deltaNanos,
            x: x,
            y: y,
            keyCode: keyCode,
            buttonNumber: buttonNumber,
            clickCount: clickCount,
            scrollX: scrollX,
            scrollY: scrollY,
            scrollUnit: scrollUnit,
            displayID: displayID,
            modifierFlagsRaw: modifierFlagsRaw
        )
    }

    private mutating func read<T: FixedWidthInteger>(_ type: T.Type) -> T {
        let size = MemoryLayout<T>.size
        let end = offset + size
        let value: T = data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset = end
        return T(littleEndian: value)
    }
}
