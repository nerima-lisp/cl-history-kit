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

As of **1.0.0**, this library follows [Semantic Versioning](https://semver.org/)
and its public API is frozen. That commitment was earned rather than declared:
the API grew through 0.2.0, 0.3.0 and 0.4.0 by addition only — every new
capability (mode-aware navigation, wraparound, explicit case sensitivity on the
cursor, `history-dedup`, `history-delete-if`, `history-search`'s `:limit`)
landed as a new keyword or a new function, and no export has ever been renamed
or removed.

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
