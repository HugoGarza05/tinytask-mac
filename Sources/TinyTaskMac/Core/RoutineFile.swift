import Foundation

public enum RoutineFileError: Error, LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case malformedData

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The routine file is not a TinyTaskMac routine."
        case let .unsupportedVersion(version):
            return "This routine file uses unsupported version \(version)."
        case .malformedData:
            return "The routine file is malformed."
        }
    }
}

public enum RoutineFileCodec {
    private static let formatVersion = 1

    public static func save(_ document: RoutineDocument, to url: URL) throws {
        let storedDocument = StoredRoutineDocument(
            magic: "TinyTaskMacRoutine",
            formatVersion: formatVersion,
            appVersion: RoutineDocument.appVersion,
            createdAtMillis: UInt64(document.createdAt.timeIntervalSince1970 * 1_000),
            name: document.name,
            targetAppBundleIdentifier: document.targetAppBundleIdentifier,
            targetAppName: document.targetAppName,
            mainEntry: document.mainEntry.map { entry in
                StoredRoutineMainEntry(
                    macroReference: storedReference(for: entry.macroReference, relativeTo: url)
                )
            },
            interruptEntries: document.interruptEntries.map { entry in
                StoredRoutineInterruptEntry(
                    id: entry.id,
                    name: entry.name,
                    macroReference: storedReference(for: entry.macroReference, relativeTo: url),
                    intervalMinutes: entry.intervalMinutes,
                    priority: entry.priority,
                    isEnabled: entry.isEnabled
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storedDocument)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> RoutineDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let storedDocument: StoredRoutineDocument

        do {
            storedDocument = try decoder.decode(StoredRoutineDocument.self, from: data)
        } catch {
            throw RoutineFileError.malformedData
        }

        guard storedDocument.magic == "TinyTaskMacRoutine" else {
            throw RoutineFileError.invalidFormat
        }

        guard storedDocument.formatVersion == formatVersion else {
            throw RoutineFileError.unsupportedVersion(storedDocument.formatVersion)
        }

        return RoutineDocument(
            fileURL: url,
            createdAt: Date(timeIntervalSince1970: TimeInterval(storedDocument.createdAtMillis) / 1_000.0),
            name: storedDocument.name,
            targetAppBundleIdentifier: storedDocument.targetAppBundleIdentifier,
            targetAppName: storedDocument.targetAppName,
            mainEntry: storedDocument.mainEntry.map { entry in
                RoutineMainEntry(
                    macroReference: RoutineEntryReference(
                        relativePath: entry.macroReference.relativePath,
                        absolutePath: entry.macroReference.absolutePath
                    )
                )
            },
            interruptEntries: storedDocument.interruptEntries.map { entry in
                RoutineInterruptEntry(
                    id: entry.id,
                    name: entry.name,
                    macroReference: RoutineEntryReference(
                        relativePath: entry.macroReference.relativePath,
                        absolutePath: entry.macroReference.absolutePath
                    ),
                    intervalMinutes: entry.intervalMinutes,
                    priority: entry.priority,
                    isEnabled: entry.isEnabled
                )
            }
        )
    }

    private static func storedReference(for reference: RoutineEntryReference, relativeTo routineURL: URL) -> StoredRoutineEntryReference {
        let sourceURL = reference.resolvedURL(relativeTo: routineURL)
        if let sourceURL {
            let rebuilt = RoutinePathResolver.reference(for: sourceURL, relativeTo: routineURL)
            return StoredRoutineEntryReference(
                relativePath: rebuilt.relativePath,
                absolutePath: rebuilt.absolutePath
            )
        }

        return StoredRoutineEntryReference(
            relativePath: reference.relativePath,
            absolutePath: reference.absolutePath
        )
    }
}

enum RoutinePathResolver {
    static func reference(for macroURL: URL, relativeTo routineURL: URL?) -> RoutineEntryReference {
        let absolutePath = macroURL.standardizedFileURL.path
        let computedRelativePath: String?
        if let routineURL {
            computedRelativePath = relativePath(from: routineURL.deletingLastPathComponent(), to: macroURL)
        } else {
            computedRelativePath = nil
        }

        return RoutineEntryReference(relativePath: computedRelativePath, absolutePath: absolutePath)
    }

    private static func relativePath(from baseDirectoryURL: URL, to targetURL: URL) -> String? {
        let baseComponents = baseDirectoryURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents

        guard !baseComponents.isEmpty, !targetComponents.isEmpty else {
            return nil
        }

        var sharedIndex = 0
        while sharedIndex < min(baseComponents.count, targetComponents.count),
              baseComponents[sharedIndex] == targetComponents[sharedIndex] {
            sharedIndex += 1
        }

        if sharedIndex == 0 {
            return nil
        }

        let upward = Array(repeating: "..", count: max(0, baseComponents.count - sharedIndex))
        let downward = Array(targetComponents.dropFirst(sharedIndex))
        let combined = upward + downward
        return combined.isEmpty ? "." : NSString.path(withComponents: combined)
    }
}

private struct StoredRoutineDocument: Codable {
    let magic: String
    let formatVersion: Int
    let appVersion: String
    let createdAtMillis: UInt64
    let name: String
    let targetAppBundleIdentifier: String?
    let targetAppName: String?
    let mainEntry: StoredRoutineMainEntry?
    let interruptEntries: [StoredRoutineInterruptEntry]
}

private struct StoredRoutineEntryReference: Codable {
    let relativePath: String?
    let absolutePath: String?
}

private struct StoredRoutineMainEntry: Codable {
    let macroReference: StoredRoutineEntryReference
}

private struct StoredRoutineInterruptEntry: Codable {
    let id: UUID
    let name: String
    let macroReference: StoredRoutineEntryReference
    let intervalMinutes: Int
    let priority: Int
    let isEnabled: Bool
}
