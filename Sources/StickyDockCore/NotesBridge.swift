import Foundation

/// A note as it exists in Apple Notes.
public struct RemoteNote: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var modifiedAt: Date

    public init(id: String, title: String, text: String, modifiedAt: Date) {
        self.id = id
        self.title = title
        // Notes appends a trailing newline to every body it stores. Left alone,
        // that one character makes every freshly pushed note look changed on the
        // next poll, and the app would sync in a loop for ever.
        self.text = RemoteNote.normalise(text)
        self.modifiedAt = modifiedAt
    }

    /// Trailing whitespace carries no meaning in a sticky note, and Notes adds
    /// its own, so both sides are compared without it.
    public static func normalise(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        while out.hasSuffix("\n") || out.hasSuffix(" ") {
            out.removeLast()
        }
        return out
    }
}

public enum NotesBridgeError: Error, Equatable, CustomStringConvertible {
    /// macOS has not granted, or the user has denied, permission to control Notes.
    case notAuthorised
    case scriptMissing
    case scriptFailed(String)
    case badResponse(String)
    case remote(String)

    public var description: String {
        switch self {
        case .notAuthorised:
            return "StickyDock is not allowed to control Notes. Turn it on in "
                 + "System Settings > Privacy & Security > Automation > StickyDock."
        case .scriptMissing:   return "The Notes bridge script is missing from the app bundle."
        case .scriptFailed(let s): return "The Notes bridge failed: \(s)"
        case .badResponse(let s):  return "The Notes bridge returned something unreadable: \(s)"
        case .remote(let s):       return "Apple Notes refused: \(s)"
        }
    }
}

/// What `SyncEngine` needs from Apple Notes. The engine depends on this, never
/// on `NotesBridge`, so every sync rule is testable without touching the real app.
public protocol NotesBridging: Sendable {
    func ensureFolder(account: String, folder: String) throws
    func list(account: String, folder: String) throws -> [RemoteNote]
    func create(account: String, folder: String, text: String, knownIds: [String]) throws -> RemoteNote
    func update(account: String, folder: String, id: String, text: String) throws -> RemoteNote
    func delete(account: String, folder: String, id: String) throws
}

/// Drives Apple Notes by running a JXA script through `osascript`.
///
/// Requests go in as JSON on stdin, never as string interpolation into a script.
/// Note text is therefore always a value, never code. This is the same rule as
/// parameterised SQL, and it matters just as much: a note containing a quote
/// character would otherwise be able to change what the script does.
public final class NotesBridge: NotesBridging, @unchecked Sendable {
    // @unchecked Sendable is safe: the only stored property is an immutable URL.
    private let scriptURL: URL

    public init(scriptURL: URL) {
        self.scriptURL = scriptURL
    }

    /// The copy shipped inside the app bundle.
    public static func bundled() throws -> NotesBridge {
        guard let url = Bundle.module.url(forResource: "notes_bridge", withExtension: "js") else {
            throw NotesBridgeError.scriptMissing
        }
        return NotesBridge(scriptURL: url)
    }

    // MARK: - Operations

    public func ensureFolder(account: String, folder: String) throws {
        _ = try call(["op": "ensureFolder", "account": account, "folder": folder])
    }

    public func list(account: String, folder: String) throws -> [RemoteNote] {
        let reply = try call(["op": "list", "account": account, "folder": folder])
        guard let raw = reply["notes"] as? [[String: Any]] else {
            throw NotesBridgeError.badResponse("list had no notes array")
        }
        return try raw.map(Self.decodeNote)
    }

    public func create(
        account: String, folder: String, text: String, knownIds: [String]
    ) throws -> RemoteNote {
        let reply = try call([
            "op": "create", "account": account, "folder": folder,
            "html": NoteHTML.toHTML(text), "knownIds": knownIds,
        ])
        return try Self.decodeSingle(reply)
    }

    public func update(
        account: String, folder: String, id: String, text: String
    ) throws -> RemoteNote {
        let reply = try call([
            "op": "update", "account": account, "folder": folder,
            "id": id, "html": NoteHTML.toHTML(text),
        ])
        return try Self.decodeSingle(reply)
    }

    public func delete(account: String, folder: String, id: String) throws {
        _ = try call(["op": "remove", "account": account, "folder": folder, "id": id])
    }

    /// Cheap liveness check. Returns the account names Notes can see.
    public func accountNames() throws -> [String] {
        let reply = try call(["op": "ping"])
        return reply["accounts"] as? [String] ?? []
    }

    // MARK: - Plumbing

    private func call(_ request: [String: Any]) throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: request)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path]

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(body)
        stdin.fileHandleForWriting.closeFile()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let err = String(decoding: errData, as: UTF8.self)
        if process.terminationStatus != 0 {
            // -1743 is errAEEventNotPermitted: the Automation permission is off.
            if err.contains("-1743") || err.localizedCaseInsensitiveContains("not authorized") {
                throw NotesBridgeError.notAuthorised
            }
            throw NotesBridgeError.scriptFailed(err.isEmpty ? "exit \(process.terminationStatus)" : err)
        }

        let out = String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)),
              let dict = json as? [String: Any] else {
            throw NotesBridgeError.badResponse(out.isEmpty ? err : out)
        }
        if dict["ok"] as? Bool != true {
            let message = dict["error"] as? String ?? "unknown"
            if message.contains("-1743") { throw NotesBridgeError.notAuthorised }
            throw NotesBridgeError.remote(message)
        }
        return dict
    }

    private static func decodeSingle(_ reply: [String: Any]) throws -> RemoteNote {
        guard let raw = reply["note"] as? [String: Any] else {
            throw NotesBridgeError.badResponse("reply had no note")
        }
        return try decodeNote(raw)
    }

    /// Computed, not stored. ISO8601DateFormatter is not Sendable, so a shared
    /// static instance would be a data race under Swift 6 strict concurrency.
    /// A sync touches a handful of notes, so building one per note costs nothing.
    ///
    /// JXA's `Date.toISOString()` always emits milliseconds ("...T08:53:13.000Z")
    /// and `.withInternetDateTime` on its own rejects them, so both spellings are
    /// tried. This cost three failing integration tests to find.
    private static func parseDate(_ text: String) -> Date? {
        let candidates: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ]
        for options in candidates {
            let f = ISO8601DateFormatter()
            f.formatOptions = options
            if let date = f.date(from: text) { return date }
        }
        return nil
    }

    private static func decodeNote(_ raw: [String: Any]) throws -> RemoteNote {
        guard let id = raw["id"] as? String,
              let text = raw["text"] as? String,
              let stamp = raw["modifiedAt"] as? String,
              let modified = parseDate(stamp) else {
            throw NotesBridgeError.badResponse("note was missing a field: \(raw)")
        }
        return RemoteNote(
            id: id,
            title: raw["title"] as? String ?? NoteHTML.title(of: text),
            text: text,
            modifiedAt: modified
        )
    }
}
