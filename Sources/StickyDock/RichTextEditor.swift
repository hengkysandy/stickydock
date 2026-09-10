import AppKit
import StickyDockCore
import SwiftUI

/// The note text view.
///
/// An `NSTextView` rather than SwiftUI's `TextEditor`, for two reasons that
/// `TextEditor` cannot give at all: real bold, italic and underline on a
/// selection, and the system find bar on ⌘F.
final class NoteTextView: NSTextView {

    /// Called when the text or its formatting changes.
    var onEdit: ((RichText) -> Void)?

    /// Named `noteContent` rather than `richText` because `NSTextView` already
    /// has a `richText` property, and it is a Bool.
    var noteContent: RichText {
        get { RichTextBridge.richText(from: attributedString()) }
        set {
            let selected = selectedRange()
            textStorage?.setAttributedString(RichTextBridge.attributed(newValue, font: baseFont))
            // Keep the caret where the user left it. Without this, every sync
            // that touches this note throws the cursor back to the start.
            let length = (string as NSString).length
            setSelectedRange(NSRange(
                location: min(selected.location, length),
                length: min(selected.length, length - min(selected.location, length))
            ))
        }
    }

    var baseFont: NSFont = .systemFont(ofSize: 13)

    // MARK: - Formatting commands

    /// ⌘B. Applies to the selection, or to whatever is typed next when there is
    /// no selection, which is what every other Mac editor does.
    @objc func toggleBold(_ sender: Any?) {
        toggleTrait(.boldFontMask, unset: .unboldFontMask)
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleTrait(.italicFontMask, unset: .unitalicFontMask)
    }

    /// ⌘U. `NSText.underline(_:)` exists but toggles through a different code
    /// path than the two above, and mixing them made the state hard to reason
    /// about, so all three are handled the same way here.
    @objc func toggleUnderlineStyle(_ sender: Any?) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        if range.length == 0 {
            let current = typingAttributes[.underlineStyle] as? Int ?? 0
            typingAttributes[.underlineStyle] = current == 0
                ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        let anyPlain = !isEveryCharacterUnderlined(in: range, storage: storage)
        storage.beginEditing()
        storage.addAttribute(
            .underlineStyle,
            value: anyPlain ? NSUnderlineStyle.single.rawValue : 0,
            range: range
        )
        storage.endEditing()
        didChangeText()
    }

    private func isEveryCharacterUnderlined(in range: NSRange, storage: NSTextStorage) -> Bool {
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                allUnderlined = false
                stop.pointee = true
            }
        }
        return allUnderlined
    }

    private func toggleTrait(_ trait: NSFontTraitMask, unset: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()

        if range.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? baseFont
            let isOn = manager.traits(of: font).contains(trait)
            typingAttributes[.font] = manager.convert(font, toNotHaveTrait: isOn ? trait : unset)
            if !isOn { typingAttributes[.font] = manager.convert(font, toHaveTrait: trait) }
            return
        }

        guard let storage = textStorage else { return }
        var everyCharacterHasIt = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = value as? NSFont ?? baseFont
            if !manager.traits(of: font).contains(trait) {
                everyCharacterHasIt = false
                stop.pointee = true
            }
        }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? baseFont
            let updated = everyCharacterHasIt
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: updated, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    /// Menu items are validated against the first responder, so without this the
    /// Format menu is greyed out and the shortcuts do nothing.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)),
             #selector(toggleItalic(_:)),
             #selector(toggleUnderlineStyle(_:)):
            return isEditable
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}

/// Converts between `NSAttributedString` and the AppKit-free `RichText`.
///
/// The offsets on both sides are UTF-16, so this is a straight copy with no
/// index translation to get wrong.
enum RichTextBridge {

    static func attributed(_ rich: RichText, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: rich.text,
            attributes: [.font: font, .foregroundColor: NSColor.black]
        )
        let manager = NSFontManager.shared
        let length = (rich.text as NSString).length

        for run in rich.runs {
            let range = NSRange(location: run.location, length: run.length)
            guard range.location >= 0, range.location + range.length <= length else { continue }
            var styled = font
            if run.bold { styled = manager.convert(styled, toHaveTrait: .boldFontMask) }
            if run.italic { styled = manager.convert(styled, toHaveTrait: .italicFontMask) }
            result.addAttribute(.font, value: styled, range: range)
            if run.underline {
                result.addAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range
                )
            }
        }
        return result
    }

    static func richText(from attributed: NSAttributedString) -> RichText {
        let text = attributed.string
        let length = (text as NSString).length
        guard length > 0 else { return RichText(text: text) }

        let manager = NSFontManager.shared
        var runs: [TextStyleRun] = []
        var index = 0
        while index < length {
            var effective = NSRange(location: 0, length: 0)
            let attributes = attributed.attributes(at: index, effectiveRange: &effective)
            let font = attributes[.font] as? NSFont
            let traits = font.map { manager.traits(of: $0) } ?? []
            let run = TextStyleRun(
                location: effective.location,
                length: effective.length,
                bold: traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask),
                underline: (attributes[.underlineStyle] as? Int ?? 0) != 0
            )
            if !run.isPlain { runs.append(run) }
            index = effective.location + max(effective.length, 1)
        }
        return RichText(text: text, runs: merge(runs))
    }

    /// Attribute runs can be split for reasons that have nothing to do with
    /// styling. Merging them keeps the HTML, and therefore the sync hash,
    /// stable for text that has not actually changed.
    private static func merge(_ runs: [TextStyleRun]) -> [TextStyleRun] {
        var merged: [TextStyleRun] = []
        for run in runs.sorted(by: { $0.location < $1.location }) {
            if var last = merged.last,
               last.location + last.length == run.location,
               last.bold == run.bold, last.italic == run.italic, last.underline == run.underline {
                last.length += run.length
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged
    }
}
