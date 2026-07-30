# Recall Navigation

This is the cursor an ++arrow-up++ / ++arrow-down++ key pair drives.

```lisp
(history-kit:history-previous history current-input
  &key (mode :line-prefix) (wrap nil) case-sensitive (smartcase t))
(history-kit:history-next history)
(history-kit:history-navigating-p history)
(history-kit:history-reset-navigation history)
```

## Walking backward

`history-previous` steps one match further back and returns its text, or `nil`
when there is no older match — in which case the cursor stays where it was, so
holding ++arrow-up++ at the oldest entry does nothing rather than resetting.

```lisp
(defparameter *history*
  (let ((history (history-kit:make-history)))
    (dolist (text '("git status" "ls -la" "git commit") history)
      (history-kit:history-add history text))))
;; newest first: ("git commit" "ls -la" "git status")

(history-kit:history-previous *history* "")   ; => "git commit"
(history-kit:history-previous *history* "")   ; => "ls -la"
(history-kit:history-previous *history* "")   ; => "git status"
(history-kit:history-previous *history* "")   ; => NIL
```

On an empty store it returns `nil` and starts no walk at all.

## The frozen filter

`current-input` matters only on the **first** call of a walk. There it becomes
the filter applied to every subsequent step:

```lisp
(history-kit:history-previous *history* "git ")  ; => "git commit"
(history-kit:history-previous *history* "git ")  ; => "git status"
;;                                                  "ls -la" skipped
```

Later calls ignore the argument entirely, so the caller may pass whatever the
buffer currently shows without disturbing the walk:

```lisp
(history-kit:history-reset-navigation *history*)

(history-kit:history-previous *history* "git ")       ; => "git commit"
;; The buffer now reads "git commit", but the filter is still "git ".
(history-kit:history-previous *history* "git commit") ; => "git status"
```

This is the detail hand-rolled implementations most often lose. A cursor that
re-derived its filter from the current buffer would, on the second press, start
matching against `git commit` and jump to a different set of entries — or, more
commonly, to none at all.

### Matching rules

The filter is matched **line-prefix** under **smartcase**:

- line-prefix, so a multi-line entry is recalled by any of its lines;
- smartcase, so a lower-case filter matches loosely and one with an upper-case
  character matches exactly.

```lisp
(defparameter *mixed*
  (let ((history (history-kit:make-history)))
    (dolist (text '("git push" "Git log") history)
      (history-kit:history-add history text))))

(history-kit:history-previous *mixed* "Git")   ; => "Git log"
(history-kit:history-previous *mixed* "Git")   ; => NIL
```

An empty filter matches everything, which is why passing `""` walks the whole
history.

## Choosing a match mode

`history-previous` accepts the same four modes as [`history-search`](search.md#modes)
through `:mode`, defaulting to `:line-prefix` for a plain Up/Down key pair.
Like `current-input`, `mode` matters only on the first call of a walk:

```lisp
(defparameter *mixed-modes*
  (let ((history (history-kit:make-history)))
    (dolist (text '("git push" "ls" "git commit") history)
      (history-kit:history-add history text))))

;; A Ctrl-R-style incremental search: :CONTAINS over the same cursor a plain
;; Up/Down pair uses, no separate search state to keep in sync.
(history-kit:history-previous *mixed-modes* "s" :mode :contains) ; => "git push"
(history-kit:history-previous *mixed-modes* "s" :mode :contains) ; => "ls"
```

An unknown mode signals the same error `history-search` does. Because the mode
is frozen alongside the filter, a host can bind `:mode :line-prefix` to
++arrow-up++ / ++arrow-down++ and `:mode :contains` to ++ctrl+r++ without
maintaining two cursors or two copies of the matching logic.

## Wraparound

`history-previous` and `history-next` also accept `&key (wrap nil)`, frozen on
the first call of a walk exactly like `mode` and `current-input`. With the
default `wrap nil`, reaching either end stops the walk there: `history-previous`
returns `nil` at the oldest match, and `history-next` restores the origin at
the newest match, as described above and below. With `wrap t`, both ends
instead cycle to the other one:

```lisp
(defparameter *wrap-history*
  (let ((history (history-kit:make-history)))
    (dolist (text '("git status" "git commit" "ls -la") history)
      (history-kit:history-add history text))))
;; newest first: ("ls -la" "git commit" "git status")

(history-kit:history-previous *wrap-history* "git" :wrap t)  ; => "git commit"
(history-kit:history-previous *wrap-history* "git")          ; => "git status"
(history-kit:history-previous *wrap-history* "git")          ; => "git commit" -- past the oldest match, wraps to the newest
(history-kit:history-next *wrap-history*)                     ; => "git status" -- past the newest match, wraps to the oldest
(history-kit:history-next *wrap-history*)                     ; => "git commit"
(history-kit:history-navigating-p *wrap-history*)            ; => T
```

Wraparound and origin-restore are mutually exclusive per walk: once `wrap` is
frozen `t`, neither `history-previous` nor `history-next` ever ends the walk on
their own, no matter how many times either is called. The only ways out of a
wrapping walk are calling `history-reset-navigation` explicitly, or any
operation that already resets navigation unconditionally -- `history-add`,
`history-clear`, or a `history-delete` that removed something (see the table
under [Ending a walk](#ending-a-walk)).

## Case sensitivity

`case-sensitive` and `smartcase` are frozen on the first call exactly like
`mode` and `wrap`, and work identically to
[`history-search`'s](search.md#smartcase): `smartcase` defaults to `t` and
derives sensitivity from `current-input` itself -- a lower-case filter matches
loosely, one with an upper-case character matches exactly -- overriding
`case-sensitive`. Pass `:smartcase nil` to control sensitivity explicitly
through `case-sensitive` instead, the same override `history-search` accepts.

## Performance model

The first `history-previous` call evaluates the selected matcher over the
history once and freezes the matching entries in newest-first order. Each later
`history-previous` or `history-next` call indexes that vector in constant time;
it does not rescan the history. Any successful history mutation resets the
cursor, so the next walk always builds a current candidate set.

Returned command text is a fresh string. Changing it cannot alter the entry
stored in the history.

## Walking forward

`history-next` steps one match back toward the newest end. Stepping past the
newest match ends the walk and returns the input preserved when it began:

```lisp
(history-kit:history-reset-navigation *history*)

(history-kit:history-previous *history* "git ")  ; => "git commit"
(history-kit:history-previous *history* "git ")  ; => "git status"
(history-kit:history-next *history*)             ; => "git commit"
(history-kit:history-next *history*)             ; => "git "  -- the origin
(history-kit:history-navigating-p *history*)     ; => NIL
```

That last step is the second detail worth having: the half-written `git ` is
still there, so an accidental ++arrow-up++ costs nothing to undo. Handing back
an empty buffer instead — the usual shortcut — silently destroys work.

`history-next` returns `nil` when no walk is in progress.

## Ending a walk

```lisp
(history-kit:history-reset-navigation history)   ; => the history
```

Call this when the recalled line has been accepted or the input abandoned, so
the next ++arrow-up++ starts a fresh walk from the newest entry.

Navigation also resets **automatically** whenever entry positions shift, since a
surviving cursor would point at a different entry than the user last saw:

| Operation | Resets navigation |
| --- | --- |
| `history-add` | Always |
| `history-clear` | Always |
| `history-delete` | Only when it removed something |
| `history-merge` | Always (it records entries) |

```lisp
(history-kit:history-previous *history* "")
(history-kit:history-add *history* "pwd")
(history-kit:history-navigating-p *history*)   ; => NIL
(history-kit:history-previous *history* "")    ; => "pwd"
```

## Wiring it to keys

```lisp
(defun handle-key (history key buffer)
  "Return the new input buffer after KEY."
  (case key
    (:up   (or (history-kit:history-previous history buffer) buffer))
    (:down (or (history-kit:history-next history) buffer))
    (:enter
     (history-kit:history-add history buffer)   ; resets navigation itself
     "")
    ;; Any ordinary edit abandons the walk, so the next Up re-reads the buffer
    ;; as a fresh filter.
    (t
     (history-kit:history-reset-navigation history)
     buffer)))
```

Both `history-previous` and `history-next` return `nil` to mean "nothing
happened", which is why each is wrapped in `or ... buffer` — the buffer is left
exactly as it was.

## State summary

A store is in one of two states:

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Walking: history-previous (a match exists)
    Walking --> Walking: history-previous / history-next (a match exists)
    Walking --> Idle: history-next past the newest match
    Walking --> Idle: history-reset-navigation
    Walking --> Idle: history-add / history-clear / history-delete
```

`history-navigating-p` reports which one. While idle, the cursor holds no
filter and no origin; the next `history-previous` establishes both.
