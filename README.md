# StickyDock

Sticky notes docked to the edge of your Mac, that show up in Apple Notes on your
iPhone.

Move the pointer to the right edge of the screen and a thin stripe fans open into
a deck of tabs, each note keeping its colour and its own vertical label. Rest on
a tab for a peek at what is inside, click to open it clear of the deck, or
**drag it out onto the desktop** and it becomes a real sticky note window that
stays where you put it. Everything you
write is mirrored into a folder called **StickyDock** in Apple Notes, so the same
notes are on your phone, your iPad, and every other Mac signed into the same
Apple ID.

## Why it works this way

Most sticky-note apps that sync write their own file format into iCloud Drive.
That syncs Mac to Mac and gives the phone nothing useful, because a phone cannot
open a proprietary note file.

StickyDock does not have a sync engine. **Apple Notes is the sync engine.** The
app mirrors one Notes folder into a local cache and back, and Apple's own
infrastructure moves the data. That means:

- The iPhone needs no app. Open Notes, the notes are there.
- No account, no server, no subscription, no network code in this app at all.
- Conflict handling and offline behaviour are Apple's problem, not ours.

The cost is that Apple Notes raises no change events, so StickyDock polls: every
15 seconds while the dock is open, every 60 seconds while it is a stripe on the
edge of the screen.

## Install

1. Download the `.dmg` from [Releases](https://github.com/hengkysandy/stickydock/releases)
   and drag StickyDock to Applications.
2. Clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/StickyDock.app
   ```

3. Open it. There is **no Dock icon** by design. Look for the note icon in the
   menu bar, or move your pointer to the right edge of the screen.

**Do not use `sudo` for that command.** With `sudo` the attribute is removed as
root, which can leave the bundle owned by root and the app then fails to write
its own database. If you already did, fix it with
`sudo chown -R "$(whoami)" /Applications/StickyDock.app`.

Without step 2, macOS says the developer cannot be verified. The app is signed,
but with a free Apple Development certificate and no notarization, which needs
the paid Apple Developer Programme. Right-clicking and choosing **Open** works
too. Building it yourself skips all of this: a locally built app is never
quarantined.

On the first sync macOS asks whether StickyDock may control Notes. Say yes. If
you say no it still runs, it just stops syncing, and it will tell you so.

## Nothing happens when I open it

Run this on the Mac in question and read the four answers:

```bash
sw_vers -productVersion                                   # needs 14 or later
uname -m                                                  # arm64 or x86_64
lipo -info /Applications/StickyDock.app/Contents/MacOS/StickyDock
pgrep -x StickyDock && echo RUNNING || echo NOT RUNNING
```

- **macOS 13 or older.** It will not launch. The app needs 14.
- **`lipo` does not list your architecture.** Releases before v1.0.1 were arm64
  only and cannot start on an Intel Mac, usually with no dialog at all. Use
  v1.0.1 or later, which is universal.
- **RUNNING, but you see nothing.** It is working; you are just not finding it.
  There is no Dock icon. If you use a menu bar manager such as Ice or Bartender,
  or your Mac has a notch and a crowded menu bar, the icon is hidden. Move the
  pointer to the very right edge of the screen instead: the resting stripe is
  only 14 points wide.
- **NOT RUNNING.** Look for a crash report:

  ```bash
  ls -t ~/Library/Logs/DiagnosticReports | grep -i stickydock | head
  log show --last 5m --predicate 'process == "StickyDock"' | tail -40
  ```

## Requirements

- macOS 14 or later.
- An iCloud account with Notes turned on.
- **Automation permission.** The first time it syncs, macOS asks whether
  StickyDock may control Notes. Say yes. If you say no, the app still works, it
  just stops syncing, and it will tell you so.

No Apple Developer Program membership is needed. The build signs with whatever
Apple Development certificate is on the machine, and a free Apple ID gives you
one.

## Build and run

```bash
./scripts/build.sh    # builds and signs build/StickyDock.app (universal)
./scripts/run.sh      # builds, kills any running copy, relaunches
./scripts/package.sh  # builds the .dmg for a release
./scripts/make_icon.py  # regenerates Resources/AppIcon.icns
```

`build.sh` builds for arm64 and x86_64 together, so the result runs on both
Apple Silicon and Intel. For a faster build while working on one machine, set
`STICKYDOCK_ARCHS="arm64"`.

`build.sh` signs with a real certificate rather than ad-hoc on purpose. macOS ties
the Automation permission grant to the code signature, and an ad-hoc signature
gets a new hash on every build, so ad-hoc would make macOS re-ask "StickyDock
wants to control Notes" after every single rebuild. It picks up whichever Apple
Development certificate is in your keychain; set `STICKYDOCK_IDENTITY="..."` to
choose a specific one. With no certificate at all it falls back to ad-hoc, which
works but re-prompts for Automation on every build.

## Tests

```bash
swift test                                    # 65 tests, no side effects
STICKYDOCK_LIVE_NOTES=1 swift test --filter NotesBridgeLive   # talks to real Notes
```

The live suite works in a throwaway folder called `StickyDockTest` and removes
what it makes. It never touches your real StickyDock folder.

## Using it

| | |
|---|---|
| Open the deck | Move the pointer to the right edge of the screen |
| Peek at a note | Rest the pointer on its tab. Read-only, so a stray hover cannot change anything |
| Bold / italic / underline | ⌘B, ⌘I, ⌘U |
| Search inside a note | ⌘F, then ⌘G and ⇧⌘G for next and previous |
| Put a note on the desktop | Drag it out of the deck |
| Put it back | The `⇥` button in the note's top left corner |
| Find a buried desktop note | Menu bar › Bring Desktop Notes to Front |
| New note | `⌃⌥N` from anywhere, or the `+` in the deck, or the menu bar |
| Close the editor | The `‹` in the corner |
| Search everything | Menu bar › All Notes… |
| Force a sync | Menu bar › Sync Now |

**Formatting reaches your phone.** Bold, italic and underline are written into
the note as `<b>`, `<i>` and `<u>`, which Apple Notes keeps verbatim, so a word
bolded on the Mac is bold in Notes on the iPhone. Reading it back is deliberately
careful: the characters come from the Notes `plaintext` property, which is always
right, and only the tag positions come from the HTML body, which corrupts
entities. If the two disagree, the formatting is dropped rather than guessed at,
because putting bold on the wrong words is worse than losing it.

**Desktop notes float above other windows.** This is a deliberate difference from
Apple's Stickies, which sit at normal window level and get buried. The dock
already covers the "keep it out of my way" case, so dragging a note out is read
as an explicit request to keep it in front. One click puts it back.

Their position and size are per-Mac and stay on this machine. Screen layouts
differ between machines, so a window position is not something worth syncing. A
note parked on a monitor you later unplug is brought back onto a screen you still
have, rather than being stranded somewhere you cannot reach it.

**Archive keeps the text, delete does not.** Archiving takes the note out of the
Notes folder, so it leaves your phone, but the text stays here and stays
searchable in All Notes. Delete is permanent, and it removes the note from Apple
Notes too.

A deleted note leaves a tombstone behind for a few seconds, until the next sync
has removed it from Apple Notes. That is not tidiness, it is the whole mechanism:
without a local record the next sync would find the note still sitting in Apple
Notes, decide it was one it had never seen, and adopt it straight back. Delete
therefore needs one sync to finish, and survives a quit in between.

## What it deliberately does not do

- **It never touches a password-protected or shared note.** Those are filtered
  out of every read.
- **It only ever looks in one folder.** A note you keep elsewhere in Apple Notes
  is invisible to StickyDock and always will be.
- **It never merges two versions of a note.** If the same note is edited here and
  on the phone between two polls, both versions are kept and the second one is
  labelled `(conflict <date>)`. Guessing which edit mattered more is not
  something a sticky-note app should do.
- **It never sends anything anywhere.** There is no network code in this app.
  Your notes go to Apple, through Apple's software, exactly as they would if you
  typed them into Notes yourself.

## Note colours

Apple Notes has no custom metadata field, so a colour cannot travel with the
note. Colours live in a small file in iCloud Drive at
`~/Library/Mobile Documents/com~apple~CloudDocs/StickyDock/sidecar.json`, which
is invisible on the phone and syncs Mac to Mac.

If iCloud Drive is switched off, colours simply stay on this Mac and everything
else carries on working.

## Settings

There is no settings window yet. The two settings that exist live in
`UserDefaults`:

```bash
defaults write com.hengkysandy.stickydock notesFolder  "Stickies"
defaults write com.hengkysandy.stickydock notesAccount "iCloud"
defaults write com.hengkysandy.stickydock hotKeyEnabled -bool false
```

Quit and relaunch after changing one.

## Layout

| Path | What lives there |
|---|---|
| `Sources/StickyDockCore` | All the logic. No AppKit, so it is testable. |
| `Sources/StickyDockCore/Resources/notes_bridge.js` | The JXA that drives Notes. |
| `Sources/StickyDock` | The app: panel, views, menu, sync timer. |
| `docs/superpowers/specs` | Why it is built this way. |
| `docs/superpowers/plans` | The build plan. |
