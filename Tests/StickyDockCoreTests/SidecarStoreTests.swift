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
        store.save(Sidecar(entries: [
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
            Sidecar(entries: ["a": older]),
            Sidecar(entries: ["a": newer])
        )
        #expect(merged.entries["a"]?.color == .green)
    }

    @Test func mergeIsOrderIndependent() {
        let older = SidecarEntry(color: .pink, sortIndex: 0, updatedAt: Date(timeIntervalSince1970: 100))
        let newer = SidecarEntry(color: .green, sortIndex: 1, updatedAt: Date(timeIntervalSince1970: 200))
        let a = SidecarStore.merge(Sidecar(entries: ["k": older]),
                                   Sidecar(entries: ["k": newer]))
        let b = SidecarStore.merge(Sidecar(entries: ["k": newer]),
                                   Sidecar(entries: ["k": older]))
        #expect(a == b)
    }

    @Test func mergeKeepsEntriesPresentOnOnlyOneSide() {
        let entry = SidecarEntry(color: .purple, sortIndex: 0, updatedAt: Date())
        let merged = SidecarStore.merge(
            Sidecar(entries: ["only-local": entry]),
            Sidecar(entries: ["only-remote": entry])
        )
        #expect(merged.entries.count == 2)
    }

    @Test func isAvailableIsFalseForAnUnwritableDirectory() {
        let store = SidecarStore(directory: URL(fileURLWithPath: "/no/such/place/at/all"))
        #expect(store.isAvailable == false)
        // And it still answers, rather than crashing.
        #expect(store.load().entries.isEmpty)
        store.save(Sidecar(entries: [:]))
    }

    @Test func saveIsAtomicSoAHalfWrittenFileNeverAppears() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SidecarStore(directory: dir)
        for i in 0..<20 {
            store.save(Sidecar(entries: [
                "k": SidecarEntry(color: .blue, sortIndex: i, updatedAt: Date()),
            ]))
            #expect(store.load().entries["k"]?.sortIndex == i)
        }
    }

    @Test func aVersionOneFileIsDiscardedRatherThanMisread() throws {
        // Version 1 keys were Core Data URIs carrying this Mac's store UUID, so
        // they mean nothing to the creation-date lookup that replaced them.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-sidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {"version":1,"entries":{"x-coredata://ABC/ICNote/p12":\
        {"color":"pink","sortIndex":3,"updatedAt":"2026-01-01T00:00:00Z"}}}
        """
        try json.write(to: dir.appendingPathComponent("sidecar.json"),
                       atomically: true, encoding: .utf8)

        let loaded = SidecarStore(directory: dir).load()
        #expect(loaded.version == Sidecar.currentVersion)
        #expect(loaded.entries.isEmpty)
    }
}
