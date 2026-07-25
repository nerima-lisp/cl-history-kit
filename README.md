# cl-history-kit

[![CI](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml)
[![Publish documentation](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/docs.yml/badge.svg)](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`cl-history-kit` is a dependency-free command-history library for Common Lisp.
It provides a capacity-bounded store of recorded input lines, four search modes
with smartcase, and the prefix-filtered recall cursor that an Up/Down key pair
drives.

📖 **Full documentation:** <https://nerima-lisp.github.io/cl-history-kit/> —
installation, a guided tour of the store, search, navigation, and an API
reference. The site is built with MkDocs (Material) from `docs/`; build it
locally with `nix build .#docs`.

## Why a library for this?

Every interactive program eventually grows a history: a shell, a REPL, a
multiplexer's command prompt. The list-with-a-cursor looks trivial, so it gets
rewritten each time — and each rewrite loses a different detail. Two of them
matter enough to be the reason this library exists:

- **The filter is frozen when the walk begins.** Type `git ` and press Up and
  you walk only the entries starting with `git `, and keep walking those even
  though the buffer now shows a recalled command that no longer resembles the
  original prefix.
- **The in-progress input is preserved.** Walking forward past the newest match
  hands back exactly what you had typed, not an empty buffer, so an accidental
  Up is free to undo.

Everything is portable Common Lisp with no runtime dependencies. Only the test
system uses `cl-weave`.

## Installation

### Nix flake

```sh
nix build github:nerima-lisp/cl-history-kit
```

The flake also exposes `packages.<system>.cl-history-kit` and
`devShells.<system>.default`.

### ASDF

Put the repository where ASDF can find it, then load:

```lisp
(asdf:load-system "cl-history-kit")
```

## Quick start

```lisp
(defparameter *history* (history-kit:make-history :capacity 1000))

(history-kit:history-add *history* "git status" :exit-code 0)
(history-kit:history-add *history* "ls -la" :exit-code 0)
(history-kit:history-add *history* "git commit -m wip" :exit-code 1)

;; Recall: what an Up key does. The typed text becomes the filter.
(history-kit:history-previous *history* "git ")   ; => "git commit -m wip"
(history-kit:history-previous *history* "git ")   ; => "git status"

;; Down walks back toward the newest match, then restores what was typed.
(history-kit:history-next *history*)              ; => "git commit -m wip"
(history-kit:history-next *history*)              ; => "git "

;; Search, with smartcase on by default.
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))
;; => ("git commit -m wip" "git status")
```

## The store

```lisp
(history-kit:make-history &key (capacity 10000) (duplicate-policy :remove))
```

Entries are held newest first and never exceed `capacity`; recording past it
drops the oldest. `duplicate-policy` decides what happens when recorded text
repeats a stored entry:

| Policy | Behaviour |
| --- | --- |
| `:remove` (default) | The older copy is dropped, so a repeated command moves to the top. |
| `:keep` | Every entry is recorded verbatim, preserving an exact chronological log. |

```lisp
(history-kit:history-add history text &key exit-code timestamp)
(history-kit:history-clear history)
(history-kit:history-delete history text &key (case-sensitive t))
(history-kit:history-merge target source)

(history-kit:history-entries history)          ; a fresh list, newest first
(history-kit:history-count history)
(history-kit:history-capacity history)
(history-kit:history-empty-p history)
(history-kit:history-duplicate-policy history)
```

`history-add` returns two values, the store and the entry just recorded. It
also resets navigation, because adding an entry shifts every index. `history-merge`
accepts a history or a plain list of entries and preserves each entry's original
timestamp and exit code, so loading a persisted history does not restamp it.

## Entries

```lisp
(history-kit:make-history-entry text &key timestamp exit-code)

(history-kit:history-entry-text entry)
(history-kit:history-entry-timestamp entry)     ; universal time
(history-kit:history-entry-exit-code entry)     ; integer, or NIL
(history-kit:history-entry-texts entries)
```

An entry is immutable: every slot is read-only, `text` is copied on
construction, and there is no copier.

## Search

```lisp
(history-kit:history-search history query
  &key (mode :prefix) case-sensitive (smartcase t))

(history-kit:history-entry-match-p entry query &key (mode :prefix) case-sensitive)
(history-kit:history-entry-line-suffix entry query &key case-sensitive)
```

`mode` is one of:

| Mode | Matches when |
| --- | --- |
| `:prefix` (default) | the entry text starts with the query |
| `:exact` | the entry text equals the query |
| `:contains` | the query occurs anywhere in the entry text |
| `:line-prefix` | any line of a multi-line entry starts with the query |

`smartcase` defaults to true and derives sensitivity from the query itself: an
all-lower-case query matches loosely, one containing an upper-case character
matches exactly. It overrides `case-sensitive`; pass `:smartcase nil` to control
sensitivity explicitly.

`history-entry-line-suffix` returns the text an autosuggestion would append —
the remainder of the first matching line. It returns `nil` when nothing matched
and `""` when a line is exactly the query, so "no match" and "already complete"
stay distinguishable.

## Navigation

```lisp
(history-kit:history-previous history current-input)
(history-kit:history-next history)
(history-kit:history-navigating-p history)
(history-kit:history-reset-navigation history)
```

`history-previous` steps one match further back and returns its text, or `nil`
when there is no older match. On the first call `current-input` becomes both the
filter for the whole walk and the origin restored later, so later calls may pass
whatever the buffer currently shows without disturbing the walk. Matching is
line-prefix under smartcase, so a multi-line entry is recalled by any of its
lines.

`history-next` steps back toward the newest match, and stepping past it ends the
walk and returns the preserved input. It returns `nil` when no walk is in
progress.

Navigation resets automatically whenever entry positions shift — on
`history-add`, `history-clear`, and a `history-delete` that removed something.
Call `history-reset-navigation` when a recalled line has been accepted or
abandoned.

## Error handling

Invalid arguments signal `type-error` via `check-type`, and an unknown search
mode signals the error from `ecase`. There are no library-specific condition
types in 0.1.0.

## Testing

```sh
sbcl --script run-tests.lisp
```

or:

```sh
nix flake check
```

## Scope

In scope: the in-memory store, its operations, search, and the recall cursor.

Out of scope for 0.1.0, and deliberately left to the host: file persistence
(load/save), the terminal key bindings that call `history-previous` /
`history-next`, and any shell-specific parsing of entry text such as `!!`-style
history expansion or last-argument extraction.

## License

MIT. See [LICENSE](LICENSE).
