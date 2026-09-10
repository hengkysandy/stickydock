# StickyDock — design

**Date:** 2026-09-10
**Status:** approved (user granted the full workflow up front)
**Tier:** Personal / single user. No PII beyond the user's own notes. No server.
**Compute:** none. A local macOS app. Apple's iCloud is the only remote party.

---

## 1. What it is

A macOS app that keeps sticky notes docked to the edge of the screen, and mirrors
them into a folder in Apple Notes so the same notes appear on the iPhone and on
any other Mac signed into the same Apple ID.

Inspired by holdmynotes.app. The difference that matters: holdmynotes syncs its
own files through iCloud Drive and is Mac-to-Mac only. StickyDock uses Apple
Notes as the transport, so the phone works with no extra app.

## 2. Why Apple Notes is the sync engine

Writing a sync engine means writing a conflict model, a file format, a change
feed, and a merge strategy, and then trusting it with the only copy of the data.
Apple already ships all of that and it already runs on the phone.

The spike (see `NOTES.md`) confirmed the bridge is viable:

- Notes.app is scriptable through JXA.
- Every note has a stable id that survives edits.
- Create, read, update and delete all work.
- Warm calls cost about 0.13s, so a poll loop is cheap.

What we give up:

- **No push.** Notes.app raises no change events, so we poll. 15s while the app
  is in use, 60s when idle. Good enough for sticky notes.
- **No custom metadata.** Handled by a sidecar file, see section 5.
- **Automation permission.** macOS will prompt once for "StickyDock wants to
  control Notes". If denied, the app still works, it just stops syncing.
- **Password-protected and shared notes.** Skipped. Reading them through
  automation fails or prompts. The `password protected` and `shared` properties
  let us filter them out cleanly.

## 3. Architecture

Five units. Each is testable on its own.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  DockPanel   │────▶│  NoteStore   │◀───▶│ SyncEngine   │
│  (AppKit UI) │     │  (GRDB/SQLite)│     │  (decisions) │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
                            ┌────────────────────┴─────────┐
                            ▼                              ▼
                     ┌──────────────┐             ┌─────────────────┐
                     │ NotesBridge  │             │ SidecarStore    │
                     │ (JXA→Notes)  │             │ (iCloud Drive)  │
                     └──────────────┘             └─────────────────┘
```

| Unit | Does | Depends on |
|---|---|---|
| `NoteStore` | Local SQLite cache. CRUD, search, archive, ordering. | GRDB |
| `NotesBridge` | Talks to Notes.app. list / create / update / delete. | JXA via `osascript` |
| `SidecarStore` | Reads and writes the colors JSON in iCloud Drive. | Foundation |
| `SyncEngine` | Decides what to push, pull, or flag as a conflict. | protocols only |
| `DockPanel` | The edge stripe, the fanned deck, the editor. | AppKit + SwiftUI |

`SyncEngine` depends on `NoteStoring` and `NotesBridging` **protocols**, never on
the concrete types. That is what makes the sync rules unit-testable without
touching the real Notes.app.

## 4. The Notes bridge

One JXA script per operation, invoked with `osascript -l JavaScript`, arguments
passed as JSON on stdin, results returned as JSON on stdout.

Rules learned from the spike, all encoded in the bridge:

1. **Address notes by `id`, never by `name`.** The name is the body's first line
   and changes constantly.
2. **Set `body` only, never `name`.** Setting both makes Notes duplicate the
   title line.
3. **Write HTML to `body`, read text from `plaintext`.** The `body` getter
   corrupts entities by dropping the trailing semicolon. `plaintext` is correct.
4. **Text to HTML:** escape `& < >`, split on newline, wrap each line in
   `<div>`, render an empty line as `<div><br></div>`.
5. **Skip** notes where `password protected` or `shared` is true.

Target folder: an account and folder the user picks, default iCloud /
`StickyDock`. Created on first run if missing.

## 5. The sidecar

Apple Notes has no place to hang a color. Three options were considered:

| Option | Verdict |
|---|---|
| Keep colors only in the local DB | Rejected. Colors would not reach the second Mac. |
| Encode a marker line in the note body | Rejected. Visible junk on the iPhone. |
| **Sidecar JSON in iCloud Drive** | **Chosen.** Invisible on iPhone, syncs Mac to Mac. |

Path: `~/Library/Mobile Documents/com~apple~CloudDocs/StickyDock/sidecar.json`

**This needs no Apple Developer entitlement and no paid membership.** Verified on
this machine. The paid iCloud entitlement
(`com.apple.developer.ubiquity-container-identifiers`) applies only to *sandboxed*
apps using a private ubiquity container. StickyDock is not sandboxed, so it writes
to that path as an ordinary directory and the iCloud daemon syncs it like any
folder made in Finder.

**Graceful degradation.** If the path does not exist or is not writable, the app
logs it once, keeps colors in the local DB only, and carries on. Colors then stop
travelling between Macs. Nothing else is affected and no note text is at risk.

```json
{
  "version": 1,
  "entries": {
    "<notes-id>": { "color": "yellow", "pinned": false, "sortIndex": 3,
                    "updatedAt": "2026-09-10T08:41:43Z" }
  }
}
```

Merged per entry by `updatedAt`, newest wins. The file is small and rarely
written, so the risk of a real conflict is low, and losing a color is not
data loss. Notes text is never stored here.

## 6. Sync rules

Each local note carries three fields that drive the decision:

- `notesId` — the Apple Notes id, or null if not pushed yet.
- `localHash` — SHA-256 of the current local text.
- `syncedHash` — the hash as of the last successful sync in either direction.

For each note, compare `localHash != syncedHash` (local changed) against
`remoteHash != syncedHash` (remote changed):

| Local changed | Remote changed | Action |
|---|---|---|
| no | no | nothing |
| yes | no | push local to Notes, set `syncedHash = localHash` |
| no | yes | pull remote into cache, set `syncedHash = remoteHash` |
| yes | yes | **conflict** |
| new local, no `notesId` | — | create in Notes, store the returned id |
| — | present in Notes, unknown id | create locally |
| has `notesId`, gone from Notes | — | archive locally, never hard delete |
| deleted locally | — | delete in Notes (goes to Recently Deleted) |

**Conflict rule: never lose text.** Keep the local version as-is, and create a
second note titled `<title> (conflict 2026-09-10 15:41)` holding the remote text.
The user resolves it by hand. A sticky-note app has no business guessing.

**Loop-breaking.** Pushing to Notes bumps the remote modification date, which
would look like a remote change on the next poll. Hashes, not timestamps, decide.
After a push we store the hash we wrote, so the next poll sees no difference.

## 7. UI

Three states, following holdmynotes' shape because it is a genuinely good idea.

- **Dormant.** A 12pt stripe on the chosen screen edge. One rounded dot per
  active note, in the note's color. Always on top, on every Space.
- **Fanned.** Mouse enters the stripe, the panel widens to ~320pt and the notes
  fan out as overlapping cards, newest on top.
- **Expanded.** Click a card, it opens into an editor with the body, a color
  picker, archive, and delete.

Implementation: one `NSPanel` subclass, `.nonactivatingPanel` style, floating
level, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`.

Hover is detected with an `NSTrackingArea` **inside our own window**. This is
deliberate: a global mouse monitor would need Accessibility permission, and a
sticky-note app should not ask for that.

New-note hotkey uses Carbon `RegisterEventHotKey`, which also needs no
Accessibility permission, unlike `NSEvent.addGlobalMonitorForEvents`. Default
`⌃⌥N`. A menu bar item gives a permission-free fallback.

`LSUIElement = true` so there is no Dock icon.

## 8. Testing

Swift Testing (`import Testing`), which ships with Swift 6.3.

| Layer | Covered by |
|---|---|
| Text ↔ HTML conversion | Unit. Entities, blank lines, unicode, the `&amp;` trap. |
| `SyncEngine` decision table | Unit, against a fake bridge. Every row of section 6. |
| Conflict path | Unit. Asserts both texts survive. |
| `NoteStore` | Unit against a temp on-disk DB. CRUD, search, archive, migration. |
| `SidecarStore` | Unit. Merge by `updatedAt`, corrupt file, missing file. |
| `NotesBridge` | Integration, opt-in via `STICKYDOCK_LIVE_NOTES=1`, against a
  throwaway `StickyDockTest` folder it creates and removes. |
| UI | Driven by hand in the real app before this is called done. |

## 9. Security decisions

- **No AES-GCM on the local cache**, a deliberate deviation from my global
  standards. The identical text sits unencrypted in Apple Notes' own store, so
  encrypting our copy protects nothing and adds key management. FileVault covers
  disk-at-rest. If a note needs real secrecy it belongs in a password-protected
  Apple Note, which StickyDock deliberately refuses to touch.
- **No network code at all.** The app opens no sockets. iCloud transport is
  Apple's, over TLS.
- **No analytics, no crash reporting, no telemetry.**
- **Not sandboxed.** Sending Apple Events to Notes and reading a path in iCloud
  Drive both need it. The app is for one user on their own machines.
- **Code signing.** Signed with the existing free-account certificate
  `Apple Development: <your Apple ID> (<team>)`, not ad-hoc. macOS keys
  the TCC Automation grant to the code signature, and an ad-hoc signature changes
  its hash on every build, which would re-prompt for "control Notes" every time.
  A stable certificate means the user approves once. Not notarized, which is fine
  for a locally built app: no quarantine flag, so Gatekeeper never sees it.
- **JXA injection.** Note text is never concatenated into a script. Arguments go
  in as JSON on stdin and are parsed by the script. This is the same discipline
  as parameterized SQL.

## 10. Out of scope for v1

Tags, rich text, attachments, images, checklists, reminders, multi-window, a
Windows or web client, sharing, and any paid licensing. Export is v1.1.
