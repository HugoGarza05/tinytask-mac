import CoreGraphics
import Foundation

public enum MacroFileError: Error, LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case malformedData

    public var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "The macro file is not a TinyTaskMac recording."
        case let .unsupportedVersion(version):
            return "This macro file uses unsupported version \(version)."
        case .malformedData:
            return "The macro file is malformed."
        }
    }
}

public enum MacroFileCodec {
    private static let magic: UInt32 = 0x544D_4143
    private static let formatVersion: UInt16 = 1

    public static func save(_ document: MacroDocument, to url: URL) throws {
        var writer = BinaryWriter()
        writer.write(magic)
        writer.write(formatVersion)
        writer.write(MacroEventRecord.recordVersion)
        writer.write(UInt64(document.createdAt.timeIntervalSince1970 * 1_000))
        writer.write(document.displayLayoutHash)
        writer.write(document.settings.playbackMode.rawValue)
        writer.write(document.settings.targetLockMode.rawValue)
        writer.write(document.settings.repeatMode.rawValue)
        writer.write(UInt8(0))
        writer.write(document.settings.playbackSpeedMultiplier)
        writer.write(UInt64(document.displays.count))
        writer.write(UInt64(document.events.count))
        writer.write(document.target.windowTitleHash)
        writer.write(document.target.frame.origin.x)
        writer.write(document.target.frame.origin.y)
        writer.write(document.target.frame.size.width)
        writer.write(document.target.frame.size.height)
        writer.write(document.target.displayID)
        writer.write(document.target.backingScale)
        writer.writeString(MacroDocument.appVersion)
        writer.writeString(document.target.bundleIdentifier)
        writer.writeString(document.target.applicationName)
        writer.writeString(document.target.windowTitle)
        writer.writeString(document.target.role)
        writer.writeString(document.target.subrole)

        for display in document.displays {
            writer.write(display.id)
            writer.write(display.frame.origin.x)
            writer.write(display.frame.origin.y)
            writer.write(display.frame.size.width)
            writer.write(display.frame.size.height)
            writer.write(display.scale)
        }

        for event in document.events {
            writer.write(event.kind.rawValue)
            writer.write(UInt8(0))
            writer.write(UInt16(0))
            writer.write(event.flagsRaw)
            writer.write(event.deltaNanos)
            writer.write(event.x)
            writer.write(event.y)
            writer.write(event.keyCode)
            writer.write(event.buttonNumber)
            writer.write(event.clickCount)
            writer.write(event.scrollX)
            writer.write(event.scrollY)
            writer.write(event.scrollUnit)
            writer.write(UInt8(0))
            writer.write(UInt16(0))
            writer.write(event.displayID)
            writer.write(event.modifierFlagsRaw)
        }

        try writer.data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> MacroDocument {
        let data = try Data(contentsOf: url)
        var reader = BinaryReader(data: data)

        guard reader.read(UInt32.self) == magic else {
            throw MacroFileError.invalidMagic
        }

        let version = reader.read(UInt16.self)
        guard version == formatVersion else {
            throw MacroFileError.unsupportedVersion(version)
        }

        let recordVersion = reader.read(UInt16.self)
        guard recordVersion == MacroEventRecord.recordVersion else {
            throw MacroFileError.unsupportedVersion(recordVersion)
        }

        let createdAtMillis = reader.read(UInt64.self)
        let displayLayoutHash = reader.read(UInt64.self)

        guard
            let playbackMode = PlaybackMode(rawValue: reader.read(UInt8.self)),
            let targetLockMode = TargetLockMode(rawValue: reader.read(UInt8.self)),
            let repeatMode = RepeatMode(rawValue: reader.read(UInt8.self))
        else {
            throw MacroFileError.malformedData
        }

        _ = reader.read(UInt8.self)
        let playbackSpeedMultiplier = reader.read(Double.self)
        let displayCount = reader.read(UInt64.self)
        let eventCount = reader.read(UInt64.self)
        let windowTitleHash = reader.read(UInt64.self)
        let targetFrame = CGRect(
            x: reader.read(Double.self),
            y: reader.read(Double.self),
            width: reader.read(Double.self),
            height: reader.read(Double.self)
        )
        let targetDisplayID = reader.read(UInt32.self)
        let targetScale = reader.read(Double.self)

        let appVersion = try reader.readString()
        _ = appVersion
        let bundleID = try reader.readString()
        let applicationName = try reader.readString()
        let windowTitle = try reader.readString()
        let role = try reader.readString()
        let subrole = try reader.readString()

        var displays: [DisplayDescriptor] = []
        displays.reserveCapacity(Int(displayCount))
        for _ in 0..<displayCount {
            displays.append(DisplayDescriptor(
                id: reader.read(UInt32.self),
                frame: CGRect(
                    x: reader.read(Double.self),
                    y: reader.read(Double.self),
                    width: reader.read(Double.self),
                    height: reader.read(Double.self)
                ),
                scale: reader.read(Double.self)
            ))
        }

        var events: [MacroEventRecord] = []
        events.reserveCapacity(Int(eventCount))
        for _ in 0..<eventCount {
            guard let kind = MacroEventKind(rawValue: reader.read(UInt8.self)) else {
                throw MacroFileError.malformedData
            }
            _ = reader.read(UInt8.self)
            _ = reader.read(UInt16.self)

            events.append(MacroEventRecord(
                kind: kind,
                flagsRaw: reader.read(UInt64.self),
                deltaNanos: reader.read(UInt64.self),
                x: reader.read(Double.self),
                y: reader.read(Double.self),
                keyCode: reader.read(UInt16.self),
                buttonNumber: reader.read(UInt8.self),
                clickCount: reader.read(UInt8.self),
                scrollX: reader.read(Int32.self),
                scrollY: reader.read(Int32.self),
                scrollUnit: reader.read(UInt8.self),
                displayID: {
                    _ = reader.read(UInt8.self)
                    _ = reader.read(UInt16.self)
                    return reader.read(UInt32.self)
                }(),
                modifierFlagsRaw: reader.read(UInt64.self)
            ))
        }

        if !reader.isAtEnd {
            throw MacroFileError.malformedData
        }

        return MacroDocument(
            fileURL: url,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAtMillis) / 1_000.0),
            displays: displays,
            displayLayoutHash: displayLayoutHash,
            target: WindowTarget(
                bundleIdentifier: bundleID,
                applicationName: applicationName,
                windowTitle: windowTitle,
                windowTitleHash: windowTitleHash,
                role: role,
                subrole: subrole,
                frame: targetFrame,
                displayID: targetDisplayID,
                backingScale: targetScale
            ),
            settings: MacroSettings(
                playbackMode: playbackMode,
                targetLockMode: targetLockMode,
                repeatMode: repeatMode,
                playbackSpeedMultiplier: playbackSpeedMultiplier
            ),
            events: events
        )
    }
}

private struct BinaryWriter {
    fileprivate(set) var data = Data()

    mutating func write(_ value: UInt8) {
        data.append(value)
    }

    mutating func write(_ value: UInt16) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: UInt32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Int32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func write(_ value: Double) {
        write(value.bitPattern)
    }

    mutating func writeString(_ string: String) {
        let bytes = Array(string.utf8)
        write(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }
}

private struct BinaryReader {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func read(_ type: UInt8.Type) -> UInt8 {
        let result: UInt8 = data[offset]
        offset += MemoryLayout<UInt8>.size
        return result
    }

    mutating func read(_ type: UInt16.Type) -> UInt16 {
        readInteger(type)
    }

    mutating func read(_ type: UInt32.Type) -> UInt32 {
        readInteger(type)
    }

    mutating func read(_ type: UInt64.Type) -> UInt64 {
        readInteger(type)
    }

    mutating func read(_ type: Int32.Type) -> Int32 {
        readInteger(type)
    }

    mutating func read(_ type: Double.Type) -> Double {
        Double(bitPattern: read(UInt64.self))
    }

    mutating func readString() throws -> String {
        let count = Int(read(UInt32.self))
        guard offset + count <= data.count else {
            throw MacroFileError.malformedData
        }

        let subdata = data[offset..<(offset + count)]
        offset += count

        guard let string = String(data: subdata, encoding: .utf8) else {
            throw MacroFileError.malformedData
        }

        return string
    }

    private mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) -> T {
        let end = offset + MemoryLayout<T>.size
        let value: T = data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset = end
        return T(littleEndian: value)
    }
}
