// StickyDock <-> Apple Notes bridge.
//
// Reads one JSON request on stdin, prints one JSON response on stdout.
// Nothing is ever interpolated into a script string: note text arrives as JSON
// and stays a JavaScript value. Same discipline as parameterised SQL.
//
// Rules the spike proved, all enforced here:
//   * Address notes by id, never by name. The name is the body's first line and
//     changes the moment the user edits it.
//   * Set `body` only, never `name`. Setting both makes Notes duplicate the
//     title line.
//   * Write HTML to `body`, read text from `plaintext`. The `body` getter drops
//     the trailing semicolon off entities, so it is not safe to read.
ObjC.import('Foundation');

function readStdin() {
  var handle = $.NSFileHandle.fileHandleWithStandardInput;
  var data = handle.readDataToEndOfFile;
  return ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
}

function iso(date) {
  return date ? date.toISOString() : null;
}

// Notes we must not touch. Reading a password-protected note fails or prompts,
// and a shared note belongs to someone else's sync too.
function isSkippable(note) {
  try { if (note.passwordProtected()) return true; } catch (e) {}
  try { if (note.shared()) return true; } catch (e) {}
  return false;
}

function findAccount(Notes, name) {
  var accounts = Notes.accounts.whose({ name: name })();
  if (accounts.length === 0) {
    throw new Error('no Notes account named "' + name + '"');
  }
  return accounts[0];
}

function findFolder(account, name, createIfMissing) {
  var folders = account.folders.whose({ name: name })();
  if (folders.length > 0) return folders[0];
  if (!createIfMissing) throw new Error('no folder named "' + name + '"');
  var Notes = Application('Notes');
  var folder = Notes.Folder({ name: name });
  account.folders.push(folder);
  return account.folders.whose({ name: name })()[0];
}

// Notes has no global lookup by id that works reliably, so scan the folder.
function findNoteById(folder, id) {
  var notes = folder.notes();
  for (var i = 0; i < notes.length; i++) {
    if (notes[i].id() === id) return notes[i];
  }
  throw new Error('no note with id ' + id + ' in that folder');
}

function describe(note) {
  return {
    id: note.id(),
    title: note.name(),
    // plaintext is the authority for the characters: the body getter corrupts
    // entities. The body comes along only so formatting ranges can be recovered.
    text: note.plaintext(),
    body: note.body(),
    modifiedAt: iso(note.modificationDate())
  };
}

var OPS = {
  ping: function () {
    var Notes = Application('Notes');
    return { accounts: Notes.accounts().map(function (a) { return a.name(); }) };
  },

  ensureFolder: function (req) {
    var Notes = Application('Notes');
    var account = findAccount(Notes, req.account);
    var folder = findFolder(account, req.folder, true);
    return { folder: folder.name() };
  },

  list: function (req) {
    var Notes = Application('Notes');
    var folder = findFolder(findAccount(Notes, req.account), req.folder, true);
    var out = [];
    var notes = folder.notes();
    for (var i = 0; i < notes.length; i++) {
      if (isSkippable(notes[i])) continue;
      out.push(describe(notes[i]));
    }
    return { notes: out };
  },

  create: function (req) {
    var Notes = Application('Notes');
    var folder = findFolder(findAccount(Notes, req.account), req.folder, true);

    // The ids are snapshotted here, inside the same call that creates the note,
    // rather than being passed in by the caller. Two earlier bugs came from
    // trusting a caller-supplied list: creating two notes in one sync pass sent
    // the same stale list twice and mapped both local notes onto one note in
    // Notes, and any password-protected note in the folder was missing from the
    // list (the listing filters those out) so it was picked as "the new one".
    var before = {};
    var existing = folder.notes();
    for (var i = 0; i < existing.length; i++) { before[existing[i].id()] = true; }

    // body only. Passing `name` here would make Notes prepend a duplicate title.
    var note = Notes.Note({ body: req.html });
    folder.notes.push(note);

    var after = folder.notes();
    for (var j = 0; j < after.length; j++) {
      if (!before[after[j].id()]) { return { note: describe(after[j]) }; }
    }
    throw new Error('created a note but could not find it again');
  },

  update: function (req) {
    var Notes = Application('Notes');
    var folder = findFolder(findAccount(Notes, req.account), req.folder, true);
    var note = findNoteById(folder, req.id);
    note.body = req.html;
    return { note: describe(note) };
  },

  remove: function (req) {
    var Notes = Application('Notes');
    var folder = findFolder(findAccount(Notes, req.account), req.folder, true);
    var note = findNoteById(folder, req.id);
    Notes.delete(note);
    return { deleted: req.id };
  }
};

function run() {
  var raw = readStdin();
  var req;
  try {
    req = JSON.parse(raw);
  } catch (e) {
    return JSON.stringify({ ok: false, error: 'bad request JSON: ' + e.message });
  }
  var op = OPS[req.op];
  if (!op) return JSON.stringify({ ok: false, error: 'unknown op: ' + req.op });
  try {
    var result = op(req);
    result.ok = true;
    return JSON.stringify(result);
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e.message || e) });
  }
}
