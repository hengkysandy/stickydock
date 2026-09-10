import Foundation
import Testing
@testable import StickyDockCore

@Suite("SidecarStore")
struct SidecarStoreTests {

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-sidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadOfMissingFileReturnsAnEmptySidecar() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SidecarStore(directory: dir).load().entries.isEmpty)
    }

    @Test func loadOfCorruptJSONReturnsEmptyAndDoesNotThrow() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "this is not json { { {".write(
            to: dir.appendingPathComponent("sidecar.json"), atomically: true, encoding: .utf8
        )
        // A corrupt colour file must never stop the app. Losing a colour is not
        // losing data; the note text lives in Apple Notes.
        #expect(SidecarStore(directory: dir).load().entries.isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SidecarStore(directory: dir)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(Sidecar(version: 1, entries: [
            "x-coredata://a/ICNote/p1": SidecarEntry(color: .blue, sortIndex: 3, updatedAt: stamp),
        ]))
        let loaded = store.load()
        #expect(loaded.entries["x-coredata://a/ICNote/p1"]?.color == .blue)
        #expect(loaded.entries["x-coredata://a/ICNote/p1"]?.sortIndex == 3)
    }

    @Test func mergeKeepsTheEntryWithTheNewerTimestamp() {
        let older = SidecarEntry(color: .pink, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let newer = SidecarEntry(color: .green, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 200))
        let merged = SidecarStore.merge(
            Sidecar(version: 1, entries: ["a": older]),
            Sidecar(version: 1, entries: ["a": newer])
        )
        #expect(merged.entries["a"]?.color == .green)
    }

    @Test func mergeIsOrderIndependent() {
        let older = SidecarEntry(color: .pink, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let newer = SidecarEntry(color: .green, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 200))
        let a = SidecarStore.merge(Sidecar(version: 1, entries: ["k": older]),
                                   Sidecar(version: 1, entries: ["k": newer]))
        let b = SidecarStore.merge(Sidecar(version: 1, entries: ["k": newer]),
                                   Sidecar(version: 1, entries: ["k": older]))
        #expect(a == b)
    }

    @Test func mergeKeepsEntriesPresentOnOnlyOneSide() {
        let entry = SidecarEntry(color: .purple, sortIndex: 0, updatedAt: Date())
        let merged = SidecarStore.merge(
            Sidecar(version: 1, entries: ["only-local": entry]),
            Sidecar(version: 1, entries: ["only-remote": entry])
        )
        #expect(merged.entries.count == 2)
    }

    @Test func isAvailableIsFalseForAnUnwritableDirectory() {
        let store = SidecarStore(directory: URL(fileURLWithPath: "/no/such/place/at/all"))
        #expect(store.isAvailable == false)
        // And it still answers, rather than crashing.
        #expect(store.load().entries.isEmpty)
        store.save(Sidecar(version: 1, entries: [:]))
    }

    @Test func saveIsAtomicSoAHalfWrittenFileNeverAppears() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SidecarStore(directory: dir)
        for i in 0..<20 {
            store.save(Sidecar(version: 1, entries: [
                "k": SidecarEntry(color: .blue, sortIndex: i, updatedAt: Date()),
            ]))
            #expect(store.load().entries["k"]?.sortIndex == i)
        }
    }
}
