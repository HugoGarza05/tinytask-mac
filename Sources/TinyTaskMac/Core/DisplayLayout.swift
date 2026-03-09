import AppKit
import Foundation

public enum DisplayLayout {
    public static func snapshot() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = displayID(for: screen) else {
                return nil
            }

            return DisplayDescriptor(
                id: displayID,
                frame: screen.frame,
                scale: Double(screen.backingScaleFactor)
            )
        }
        .sorted { $0.id < $1.id }
    }

    public static func hash(_ displays: [DisplayDescriptor]) -> UInt64 {
        var hasher = FNV64()
        for display in displays.sorted(by: { $0.id < $1.id }) {
            hasher.combine(display.id)
            hasher.combine(display.frame.origin.x.bitPattern)
            hasher.combine(display.frame.origin.y.bitPattern)
            hasher.combine(display.frame.size.width.bitPattern)
            hasher.combine(display.frame.size.height.bitPattern)
            hasher.combine(display.scale.bitPattern)
        }
        return hasher.finalize()
    }

    public static func matchesRecorded(_ recorded: [DisplayDescriptor], current: [DisplayDescriptor], tolerance: CGFloat = 1.0) -> Bool {
        guard recorded.count == current.count else {
            return false
        }

        let lhs = recorded.sorted(by: { $0.id < $1.id })
        let rhs = current.sorted(by: { $0.id < $1.id })

        for (left, right) in zip(lhs, rhs) {
            guard left.id == right.id else {
                return false
            }

            guard left.frame.isApproximatelyEqual(to: right.frame, tolerance: tolerance) else {
                return false
            }

            guard abs(left.scale - right.scale) < 0.01 else {
                return false
            }
        }

        return true
    }

    public static func descriptor(containing point: CGPoint) -> DisplayDescriptor? {
        snapshot().first(where: { $0.frame.contains(point) }) ?? snapshot().first
    }

    public static func descriptor(for displayID: UInt32) -> DisplayDescriptor? {
        snapshot().first(where: { $0.id == displayID })
    }

    public static func displayID(containing point: CGPoint) -> UInt32 {
        descriptor(containing: point)?.id ?? 0
    }

    public static func displayID(for screen: NSScreen) -> UInt32? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }
}

private struct FNV64 {
    private var value: UInt64 = 0xcbf29ce484222325

    mutating func combine<T: FixedWidthInteger>(_ integer: T) {
        var little = integer.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            for byte in bytes {
                value ^= UInt64(byte)
                value &*= 0x100000001b3
            }
        }
    }

    func finalize() -> UInt64 {
        value
    }
}
