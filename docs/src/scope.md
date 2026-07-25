# Scope and Non-Goals

## In scope

The in-memory store, its operations, search, and the recall cursor — the parts
that are identical across every program that keeps a history, and that are
worth getting right once.

## Out of scope for 0.1.0

### Persistence

Loading and saving a history file is deliberately left to the host. The file
format, its location, when to flush, and how to handle a concurrently-writing
sibling process are all host policy, and every host answers them differently.

What the library does provide is the piece that makes persistence easy to get
right: `history-merge` preserves each entry's original timestamp and exit code,
so loading a file does not restamp every entry with the load time.

```lisp
(defun load-history (history path)
  "Merge one-entry-per-line PATH into HISTORY, oldest first."
  (with-open-file (stream path :if-does-not-exist nil)
    (when stream
      (let ((entries nil))
        (loop for line = (read-line stream nil nil)
              while line
              do (when (plusp (length line))
                   (push (history-kit:make-history-entry line) entries)))
        ;; ENTRIES is now newest-first, which is what HISTORY-MERGE expects.
        (history-kit:history-merge history entries)))))

(defun save-history (history path)
  "Write HISTORY to PATH, one entry per line, oldest first."
  (with-open-file (stream path :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
    (dolist (entry (reverse (history-kit:history-entries history)))
      (write-line (history-kit:history-entry-text entry) stream))))
```

A future release may add a persistence layer if the hosts converge on a format.

### Terminal input

The library has no opinion about keys. `history-previous` and `history-next`
are ordinary functions; binding them to ++arrow-up++ and ++arrow-down++, or to
++ctrl+p++ and ++ctrl+n++, is the host's business. See the key-handler sketch
in [Recall Navigation](navigation.md#wiring-it-to-keys).

### Shell-specific parsing of entry text

An entry's text is an opaque string. The library never parses it, so none of
the following are provided:

- `!!` / `!$` / `!n`-style history expansion
- extracting the last argument of a recorded command line
- tokenising a command to classify words, redirections, or pipelines
- deciding that a command is "not worth recording" (a leading space, a
  password-bearing invocation)

All of these need a tokeniser for a specific language, which would drag a
parser dependency into a library whose whole point is having none. A host that
needs them already has its own tokeniser; the last item is best handled by
simply not calling `history-add`.

### Rendering

Interactive search UI, ghost-text autosuggestion, and pagination of results are
presentation concerns. `history-search` and `history-entry-line-suffix` supply
the data a renderer needs; drawing it is out of scope.

## Non-goals

These are not planned at any version:

- **Fuzzy matching.** The four modes cover prefix, exact, substring, and
  per-line matching. Fuzzy scoring is a ranking problem with no single right
  answer, and a host that wants it can rank `history-entries` itself.
- **Concurrency control.** A store is a plain mutable structure with no
  locking. Hosts that share one across threads should serialise access
  themselves, which is cheaper than paying for a lock on every keystroke in the
  overwhelmingly common single-threaded case.
- **Persistent (immutable) stores.** Recording is a mutation by design; a
  history is the canonical mutable-log data structure.

## Stability

0.1.0 is a first release. The API described here is what the library's known
consumers need, but it has not yet been through a second consumer's
integration, so a 0.2.0 may still rename or re-shape parts of it. Breaking
changes will be listed in the [changelog](changelog.md).
