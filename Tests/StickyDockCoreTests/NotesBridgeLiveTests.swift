import Foundation
import Testing
@testable import StickyDockCore

/// These talk to the real Notes.app on this machine, so they are opt-in.
///
///     STICKYDOCK_LIVE_NOTES=1 swift test --filter NotesBridgeLive
///
/// They work inside a folder called `StickyDockTest` and clean up after
/// themselves. They never touch the user's real StickyDock folder.
/// `.serialized` is not optional here. Swift Testing runs tests in parallel by
/// default, and these all share one real folder in Notes, so without it they
/// delete each other's notes and fail in ways that look like bridge bugs.
@Suite(
    "NotesBridgeLive",
    .enabled(if: ProcessInfo.processInfo.environment["STICKYDOCK_LIVE_NOTES"] == "1"),
    .serialized
)
struct NotesBridgeLiveTests {
    let account = "iCloud"
    let folder = "StickyDockTest"

    private func bridge() throws -> NotesBridge { try NotesBridge.bundled() }

    /// Removes every note the tests left behind.
    private func emptyFolder(_ bridge: NotesBridge) throws {
        for note in try bridge.list(account: account, folder: folder) {
            try bridge.delete(account: account, folder: folder, id: note.id)
        }
    }

    @Test func scriptIsInTheBundle() throws {
        _ = try bridge()
    }

    @Test func pingSeesTheICloudAccount() throws {
        #expect(try bridge().accountNames().contains("iCloud"))
    }

    @Test func createListUpdateDeleteRoundTrips() throws {
        let bridge = try bridge()
        try bridge.ensureFolder(account: account, folder: folder)
        try emptyFolder(bridge)
        defer { try? emptyFolder(bridge) }

        let text = "Live test title\n\nampersand & less < greater > percent 100%"
        let created = try bridge.create(
            account: account, folder: folder, text: text, knownIds: []
        )
        #expect(created.text == text, "text must survive the HTML round trip exactly")
        #expect(created.title == "Live test title")
        #expect(created.id.hasPrefix("x-coredata://"))

        let listed = try bridge.list(account: account, folder: folder)
        #expect(listed.count == 1)
        #expect(listed.first?.id == created.id)
        #expect(listed.first?.text == text)

        let newText = "Renamed\nsecond line"
        let updated = try bridge.update(
            account: account, folder: folder, id: created.id, text: newText
        )
        #expect(updated.id == created.id, "the id must survive an edit")
        #expect(updated.text == newText)

        try bridge.delete(account: account, folder: folder, id: created.id)
        #expect(try bridge.list(account: account, folder: folder).isEmpty)
    }

    @Test func creatingTwiceGivesTwoDistinctIds() throws {
        let bridge = try bridge()
        try bridge.ensureFolder(account: account, folder: folder)
        try emptyFolder(bridge)
        defer { try? emptyFolder(bridge) }

        let first = try bridge.create(account: account, folder: folder, text: "one", knownIds: [])
        let second = try bridge.create(
            account: account, folder: folder, text: "two", knownIds: [first.id]
        )
        #expect(first.id != second.id)
        #expect(second.text == "two")
    }

    @Test func pushedTextComesBackByteIdenticalSoSyncCannotLoop() throws {
        // The whole loop-breaking guarantee rests on this. If Notes hands back
        // anything but what we sent, the hash differs and the app syncs for ever.
        let bridge = try bridge()
        try bridge.ensureFolder(account: account, folder: folder)
        try emptyFolder(bridge)
        defer { try? emptyFolder(bridge) }

        let text = "Loop check\nline two\n\nline four & <five>"
        let created = try bridge.create(account: account, folder: folder, text: text, knownIds: [])
        let listed = try bridge.list(account: account, folder: folder).first
        #expect(ContentHash.of(created.text) == ContentHash.of(text))
        #expect(ContentHash.of(listed?.text ?? "") == ContentHash.of(text))
    }

    @Test func unknownAccountReportsAClearError() throws {
        #expect(throws: NotesBridgeError.self) {
            try bridge().list(account: "NoSuchAccount", folder: folder)
        }
    }
}
