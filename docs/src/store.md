# Entries and the Store

## Entries

An entry is an immutable value object: every slot is read-only, the text is
copied on construction, and there is no copier. The store only ever conses and
drops whole entries, so nothing ever needs to mutate one.

```lisp
(history-kit:make-history-entry text &key timestamp exit-code)
```

| Slot | Type | Meaning |
| --- | --- | --- |
| `text` | `string` | The recorded input |
| `timestamp` | `integer` | Universal time; defaults to now |
| `exit-code` | `integer` or `nil` | Exit status of the command it ran |

`exit-code` is `nil` when the host tracks no exit status — a bare input prompt,
say — or has not produced one yet.

```lisp
(defparameter *entry*
  (history-kit:make-history-entry "git status" :exit-code 0))

(history-kit:history-entry-text *entry*)        ; => "git status"
(history-kit:history-entry-exit-code *entry*)   ; => 0
(history-kit:history-entry-p *entry*)           ; => T
```

Because the text is copied, a caller may keep filling a reused input buffer
after recording it:

```lisp
(let* ((buffer (make-array 2 :element-type 'character
                             :adjustable t :fill-pointer t
                             :initial-contents "ls"))
       (entry (history-kit:make-history-entry buffer)))
  (vector-push-extend #\! buffer)
  (history-kit:history-entry-text entry))
;; => "ls"   -- not "ls!"
```

`history-entry-texts` extracts the text of a whole list at once, which is what
you usually want after a search:

```lisp
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))
```

## Creating a store

```lisp
(history-kit:make-history &key (capacity 10000) (duplicate-policy :remove))
```

### Capacity

Entries are held newest first and never exceed `capacity`; recording past it
drops the oldest.

```lisp
(defparameter *small* (history-kit:make-history :capacity 2))
(history-kit:history-add *small* "a")
(history-kit:history-add *small* "b")
(history-kit:history-add *small* "c")

(history-kit:history-entry-texts (history-kit:history-entries *small*))
;; => ("c" "b")
```

A capacity of `0` is legal and records nothing. A negative or non-integer
capacity signals a `type-error`.

### Duplicate policy

| Policy | Behaviour |
| --- | --- |
| `:remove` (default) | The older copy is dropped, so a repeated command moves to the top. |
| `:keep` | Every entry is recorded verbatim, preserving an exact chronological log. |

```lisp
;; :remove -- what an interactive shell wants.
(let ((history (history-kit:make-history)))
  (history-kit:history-add history "a")
  (history-kit:history-add history "b")
  (history-kit:history-add history "a")
  (history-kit:history-entry-texts (history-kit:history-entries history)))
;; => ("a" "b")

;; :keep -- what an audit log wants.
(let ((history (history-kit:make-history :duplicate-policy :keep)))
  (history-kit:history-add history "a")
  (history-kit:history-add history "b")
  (history-kit:history-add history "a")
  (history-kit:history-entry-texts (history-kit:history-entries history)))
;; => ("a" "b" "a")
```

Note that with `:remove` it is the *older* copy that goes. Newest-first order
means the surviving entry is always the most recent one, so re-running a
command promotes it rather than leaving a stale copy above it.

## Reading a store

```lisp
(history-kit:history-entries history)          ; a fresh list, newest first
(history-kit:history-count history)
(history-kit:history-capacity history)
(history-kit:history-empty-p history)
(history-kit:history-duplicate-policy history)
```

`history-entries` returns a **fresh** list, so mutating the result cannot
corrupt the store:

```lisp
(let* ((history (history-kit:make-history))
       (entries (progn (history-kit:history-add history "ls")
                       (history-kit:history-entries history))))
  (setf (first entries) :clobbered)
  (history-kit:history-entry-texts (history-kit:history-entries history)))
;; => ("ls")
```

The entries themselves are shared rather than deep-copied, which is safe
precisely because they are immutable.

## Recording

```lisp
(history-kit:history-add history text &key exit-code timestamp)
```

Returns **two values**: the store and the entry just recorded.

```lisp
(multiple-value-bind (history entry)
    (history-kit:history-add *history* "ls -la" :exit-code 0)
  (declare (ignore history))
  (history-kit:history-entry-timestamp entry))
```

`timestamp` defaults to the current universal time. Pass it explicitly to
replay a persisted entry without restamping it.

!!! note "Recording resets navigation"

    `history-add` clears any in-progress recall walk, because adding an entry
    shifts every index — a cursor from before the addition would silently point
    at a different entry. See [Recall Navigation](navigation.md).

## Removing

```lisp
(history-kit:history-clear history)
(history-kit:history-delete history text &key (case-sensitive t))
```

`history-clear` empties the store and returns it. `history-delete` removes every
entry whose text matches exactly and returns **the number deleted**:

```lisp
(history-kit:history-delete *history* "ls -la")        ; => 1
(history-kit:history-delete *history* "LS -LA")        ; => 0
(history-kit:history-delete *history* "LS -LA" :case-sensitive nil)  ; => 1
```

Deletion is case-sensitive by default — unlike search, which uses smartcase.
Removing entries is destructive and unprompted, so it asks for an exact match
rather than guessing from the query's shape.

Navigation resets only when the delete actually removed something, so a miss
leaves an in-progress recall untouched.

## Merging

```lisp
(history-kit:history-merge target source)
```

`source` is a history or a plain newest-first list of entries. Entries are
merged in order, subject to `target`'s capacity and duplicate policy, and each
keeps its **original timestamp and exit code**:

```lisp
(let ((target (history-kit:make-history)))
  (history-kit:history-merge
   target
   (list (history-kit:make-history-entry "ls" :timestamp 11 :exit-code 3)))
  (let ((entry (first (history-kit:history-entries target))))
    (list (history-kit:history-entry-timestamp entry)
          (history-kit:history-entry-exit-code entry))))
;; => (11 3)
```

That is what makes merging usable for loading a persisted history: the entries
arrive with the times they were originally recorded, not the time the file was
read.

A `source` that is neither a history nor a list signals a `type-error`.
