# Quick Start

## Record some entries

A store keeps entries newest first and never grows past its capacity.

```lisp
(defparameter *history* (history-kit:make-history :capacity 1000))

(history-kit:history-add *history* "git status" :exit-code 0)
(history-kit:history-add *history* "ls -la" :exit-code 0)
(history-kit:history-add *history* "git commit -m wip" :exit-code 1)

(history-kit:history-count *history*)   ; => 3

(history-kit:history-entry-texts
 (history-kit:history-entries *history*))
;; => ("git commit -m wip" "ls -la" "git status")
```

Recording a command that is already stored moves it to the top instead of
leaving a stale copy behind:

```lisp
(history-kit:history-add *history* "ls -la")

(history-kit:history-entry-texts
 (history-kit:history-entries *history*))
;; => ("ls -la" "git commit -m wip" "git status")
```

That is the default `:remove` duplicate policy. Pass
`:duplicate-policy :keep` at construction for an exact chronological log
instead — see [Entries and the Store](store.md).

## Search

```lisp
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))
;; => ("git commit -m wip" "git status")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "commit" :mode :contains))
;; => ("git commit -m wip")
```

Smartcase is on by default: an all-lower-case query matches loosely, and one
containing an upper-case character matches exactly.

```lisp
(history-kit:history-add *history* "Git log")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))   ; loose
;; => ("Git log" "git commit -m wip" "git status")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "Git"))   ; exact
;; => ("Git log")
```

## Recall with Up and Down

`history-previous` is what ++arrow-up++ calls. The text currently in the input
buffer is passed in, and on the first press it becomes the filter for the whole
walk *and* the input restored at the end of it.

```lisp
(defparameter *history* (history-kit:make-history))
(history-kit:history-add *history* "git status")
(history-kit:history-add *history* "ls -la")
(history-kit:history-add *history* "git commit -m wip")

;; The user has typed "git " and presses Up.
(history-kit:history-previous *history* "git ")  ; => "git commit -m wip"
;; "ls -la" is skipped: it does not match the frozen filter.
(history-kit:history-previous *history* "git ")  ; => "git status"
;; Nothing older matches; the cursor stays put.
(history-kit:history-previous *history* "git ")  ; => NIL

;; Down walks back toward the newest match...
(history-kit:history-next *history*)             ; => "git commit -m wip"
;; ...and stepping past it restores what was typed.
(history-kit:history-next *history*)             ; => "git "

(history-kit:history-navigating-p *history*)     ; => NIL
```

## A minimal read-eval-print loop

Putting it together, this is the shape of an interactive loop's history
handling:

```lisp
(defun handle-key (history key buffer)
  "Return the new input buffer after KEY."
  (case key
    (:up   (or (history-kit:history-previous history buffer) buffer))
    (:down (or (history-kit:history-next history) buffer))
    (:enter
     (history-kit:history-add history buffer)   ; also resets navigation
     "")
    (t buffer)))
```

Note that `history-add` resets navigation on its own: recording an entry shifts
every index, so a cursor left over from before would silently point somewhere
else. See [Recall Navigation](navigation.md) for the full set of reset triggers.

## Where to next

- [Entries and the Store](store.md) — capacity, duplicate policies, merging
- [Search](search.md) — the four modes and smartcase in detail
- [Recall Navigation](navigation.md) — the cursor semantics in full
- [API Reference](api-reference.md) — every exported symbol
