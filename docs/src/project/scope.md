# Scope and Non-Goals

## In scope

The in-memory store, its operations, search, and the recall cursor — the parts
that are identical across every program that keeps a history, and that are
worth getting right once.

## Out of scope

### Persistence

Loading and saving a history file is deliberately left to the host. The file
format, its location, when to flush, and how to handle a concurrently-writing
sibling process are all host policy, and every host answers them differently.

What the library does provide are the pieces that make persistence easy to get
right. `history-entry-plist` and `history-entry-from-plist` convert an entry to
and from a property list of strings, integers, and symbols, which prints
readably. `history-merge` preserves each entry's original timestamp, exit code,
and metadata, so loading a file does not restamp every entry with the load time.

The pair below stores one plist per entry, oldest first. It reads the file with
`read` rather than line by line, because the plist of a multi-line entry spans
several lines:

```lisp
(defun load-history (history path)
  "Merge the plist records in the file at PATH into HISTORY."
  (with-open-file (stream path :if-does-not-exist nil)
    (when stream
      (let ((entries nil))
        (with-standard-io-syntax
          (let ((*read-eval* nil))
            (loop for plist = (read stream nil stream)
                  until (eq plist stream)
                  do (push (history-kit:history-entry-from-plist plist) entries))))
        ;; ENTRIES is now newest-first, which is what HISTORY-MERGE expects.
        (history-kit:history-merge history entries)))))

(defun save-history (history path)
  "Write HISTORY to PATH, one plist per entry, oldest first."
  (with-open-file (stream path :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
    (with-standard-io-syntax
      ;; WITH-STANDARD-IO-SYNTAX turns *PRINT-READABLY* on, which makes some
      ;; implementations write base strings in a non-portable syntax.
      (let ((*print-readably* nil))
        (dolist (entry (reverse (history-kit:history-entries history)))
          (prin1 (history-kit:history-entry-plist entry) stream)
          (terpri stream))))))
```

Both functions use standard I/O syntax, so a non-keyword `:origin` symbol is
printed and read relative to the same package. Binding `*read-eval*` to `nil`
makes a `#.` form in the file signal `reader-error` instead of running code at
read time. The sketch still trusts the file to be well formed. A truncated last
record makes `read` signal `end-of-file`. A record with a wrong-typed value
makes `history-entry-from-plist` signal `type-error`, and a record that is not
an even-length list makes it signal an `error`. A host loading a file that
another process or an older version may have written should handle those
conditions and skip or report the bad record instead of abandoning the whole
load. A record written before the host stored metadata, such as
`(:text "ls" :timestamp 3900000000)`, loads with `nil` metadata.

#### Migrating from the line-based format

Before 1.1.0, this page showed a pair whose saver wrote each entry's text with
`write-line` and whose loader turned each non-empty line into an entry with
`make-history-entry`, which stamped it with the load time. That line format and
the plist format above are not compatible in either direction:

- The plist loader reads an old file as Lisp data. The line `ls` reads as the
  symbol `LS`, so `history-entry-from-plist` signals `type-error`, and a line
  such as `a:b` makes `read` signal a reader error.
- The old line loader reads a plist file as text. Each line, plist syntax
  included, becomes the text of one entry, and the plist of a multi-line entry
  becomes several entries.

An old file holds one entry per non-empty line. The line format has no way to
mark a line break inside an entry, so the old saver wrote a multi-line entry as
several lines and the old loader read them back as separate entries. Because a
plist record written by `save-history` starts with `(:TEXT `, a loader can
accept old lines, plist records, and a file that mixes the two, such as an old
file to which a host has since appended plist records:

```lisp
(defun read-history-file (path &key (legacy-timestamp 0))
  "Return the entries stored at PATH, newest first, reading both formats.

A line that begins with (:TEXT starts a plist record. Any other non-empty
line is one entry in the old line-based format, recorded at LEGACY-TIMESTAMP."
  (with-open-file (stream path :if-does-not-exist nil)
    (when stream
      (let ((entries nil))
        (with-standard-io-syntax
          (let ((*read-eval* nil))
            (loop for line = (read-line stream nil nil)
                  while line
                  do (cond
                       ((zerop (length line)))
                       ((and (>= (length line) 7) (string= "(:TEXT " line :end2 7))
                        ;; The record may continue on later lines, so read it
                        ;; from this line followed by the rest of the file.
                        (push (history-kit:history-entry-from-plist
                               (read (make-concatenated-stream
                                      (make-string-input-stream
                                       (format nil "~A~%" line))
                                      stream)))
                              entries))
                       (t
                        (push (history-kit:make-history-entry
                               line :timestamp legacy-timestamp)
                              entries))))))
        entries))))
```

`(history-kit:history-merge history (read-history-file path))` then replaces
`load-history`. Like `load-history`, it lets the condition from a bad record
end the whole read. The old format stored no timestamp. `legacy-timestamp`
defaults to `0`, which marks the time as unknown; passing
`(file-write-date path)` instead dates every old entry to the file's last
write. An old entry whose text itself begins with `(:TEXT ` is handed to `read`
as a plist record and does not load as text.

To convert a file once instead, read it into a history large enough to hold
every entry and write it back with `save-history`:

```lisp
(defun convert-history-file (old-path new-path &key (capacity 100000))
  "Rewrite the history at OLD-PATH as plist records at NEW-PATH."
  (let ((history (history-kit:make-history :capacity capacity)))
    (history-kit:history-merge
     history
     (read-history-file old-path
                        :legacy-timestamp (or (file-write-date old-path) 0)))
    (save-history history new-path)))
```

Entries past `capacity` are dropped, oldest first. The conversion applies the
history's duplicate policy, so under the default `:remove` a repeated command
keeps only its newest copy, as the old loader's merge did; create the history
with `:duplicate-policy :keep` to keep every copy. A host that already versions its own file format, for example with a
header line, should keep using that version marker to choose a loader rather
than relying on the `(:TEXT ` prefix.

A future release may add a persistence layer if the hosts converge on a format.

### Terminal input

The library has no opinion about keys. `history-previous` and `history-next`
are ordinary functions; binding them to ++arrow-up++ and ++arrow-down++, or to
++ctrl+p++ and ++ctrl+n++, is the host's business. See the key-handler sketch
in [Recall Navigation](../guide/navigation.md#wiring-it-to-keys).

### Shell-specific parsing of entry text

An entry's text is an opaque string. The library never parses it, so none of
the following are provided:

- `!!` / `!$` / `!n`-style history expansion
- extracting the last argument of a recorded command line
- tokenising a command to classify words, redirections, or pipelines
- deciding that a command is "not worth recording" (a leading space, a
  password-bearing invocation)

All of these need a tokeniser for a specific language, which would drag a
parser dependency into a library whose purpose is to have none. A host that
needs them already has its own tokeniser; the last item is best handled by not
calling `history-add`.

### Rendering

Interactive search UI, ghost-text autosuggestion, and pagination of results are
presentation concerns. `history-search`, `history-fuzzy-search`, and
`history-entry-line-suffix` supply the data a renderer needs; drawing it is out of scope.

## Non-goals

These are not planned at any version:

- **Concurrency control.** A store is a plain mutable structure with no
  locking. Hosts that share one across threads should serialise access
  themselves, which is cheaper than paying for a lock on every keystroke in the
  overwhelmingly common single-threaded case.
- **Persistent (immutable) stores.** Recording is a mutation by design; a
  history is the canonical mutable-log data structure.

## Stability

As of **1.0.0**, this library follows [Semantic Versioning](https://semver.org/)
and its public API is frozen for the 1.x series. Changes in that series are
additive: new keywords preserve existing defaults, and new capabilities use new
functions or exports.

**1.1.0** is such an additive release. It adds optional entry metadata, the
plist conversion functions, allocation-free access (`history-entry-at`,
`history-newest`, `map-history`), a `filter` keyword on `history-search`, and
the `:fuzzy` mode with `history-fuzzy-search` and `history-entry-fuzzy-score`.
Code written against 1.0.0 runs unchanged: every new keyword defaults to `nil`,
which reproduces the 1.0.0 behaviour.

### What the promise covers

Within the 1.x series, none of the following will change except additively:

- The set of symbols exported from `history-kit`, and each one's name.
- Each function's lambda list: no existing parameter is removed, reordered, or
  given a different default. New behaviour arrives as a new keyword argument
  with a default preserving today's behaviour, or as a new function.
- The documented behaviour of every function, including its return
  *convention* — `nil` for "nothing happened", a count for the purge
  operations, two values from `history-add` — and the conditions under which
  navigation resets.
- Structure types `history` and `history-entry` remaining structure types with
  their current predicates and readers.

### What it does not cover

These are implementation detail, and may change in any 1.x release:

- Every `%`-prefixed internal symbol. They are unexported, undocumented and
  deliberately unstable; a caller reaching into them is not using the public
  API. This includes the `history` struct's slots, whose accessors live behind
  the private `%history-` conc-name precisely so the cursor invariants cannot
  be violated from outside.
- The identity of returned lists beyond what is documented. `history-entries`
  and `history-search` return fresh lists whose *entries* are shared, which is
  safe only because entries are immutable; nothing promises the list returned
  by two separate calls is `eq`, or that it is safe to destructively modify.
- The exact condition class and report string of a signalled error, beyond
  "a `type-error` for a wrong-typed argument, an `ecase` failure for an
  unknown mode" — see [Conditions](../reference/conditions.md). Notably, `ecase`'s
  `case-failure` is a `type-error` subtype on most implementations but is not
  required by the standard to be one.
- Performance characteristics, except where a docstring states a complexity
  (as `history-merge`'s and `history-search`'s `:limit` do).

A breaking change to anything in the first list means 2.0.0, and will be called
out explicitly in the
[release notes](https://github.com/nerima-lisp/cl-history-kit/releases).
