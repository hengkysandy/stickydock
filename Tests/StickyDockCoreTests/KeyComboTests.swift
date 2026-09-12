import Foundation
import Testing
@testable import StickyDockCore

@Suite("KeyCombo")
struct KeyComboTests {

    @Test func readsInTheUsualMacOrder() {
        // macOS always writes them control, option, shift, command, whatever
        // order they were pressed in.
        let combo = KeyCombo(
            keyCode: 45,
            modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control
        )
        #expect(combo.display == "⌃⌥⇧⌘N")
    }

    @Test func theAppsOwnDefaultReadsCorrectly() {
        #expect(KeyCombo(keyCode: 45, modifiers: KeyCombo.control | KeyCombo.option).display
                == "⌃⌥N")
    }

    @Test func namedKeysAreSpelledOut() {
        #expect(KeyCombo(keyCode: 49, modifiers: KeyCombo.command).display == "⌘Space")
        #expect(KeyCombo(keyCode: 53, modifiers: KeyCombo.option).display == "⌥Escape")
        #expect(KeyCombo(keyCode: 126, modifiers: KeyCombo.control).display == "⌃↑")
    }

    @Test func anUnknownKeyFallsBackToItsNumberRatherThanVanishing() {
        #expect(KeyCombo(keyCode: 999, modifiers: KeyCombo.command).display == "⌘Key 999")
    }

    @Test func aComboWithNoModifierIsRejectable() {
        // Binding a bare letter would swallow that key everywhere on the machine.
        #expect(KeyCombo(keyCode: 45, modifiers: 0).hasModifier == false)
        #expect(KeyCombo(keyCode: 45, modifiers: KeyCombo.command).hasModifier == true)
    }

    @Test func itSurvivesTheTripThroughSettings() throws {
        let combo = KeyCombo(keyCode: 17, modifiers: KeyCombo.command | KeyCombo.shift)
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
