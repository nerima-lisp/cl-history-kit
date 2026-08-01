# Conditions

`cl-history-kit` defines **no condition types of its own**. Invalid
arguments signal standard conditions, and no operation signals to report an
ordinary miss.

## Type errors

Every public entry point validates its arguments with `check-type`, so passing
the wrong type signals a `type-error`:

```lisp
(history-kit:make-history-entry 42)
;; => TYPE-ERROR: the value 42 is not of type STRING

(history-kit:make-history :capacity -1)
;; => TYPE-ERROR: the value -1 is not of type (INTEGER 0 *)

(history-kit:make-history :duplicate-policy :dedupe)
;; => TYPE-ERROR: the value :DEDUPE is not of type (MEMBER :REMOVE :KEEP)

(history-kit:history-count :not-a-history)
;; => TYPE-ERROR: the value :NOT-A-HISTORY is not of type HISTORY
```

`history-merge` signals a `type-error` for a source that is neither a history
nor a list, and for a list element that is not an entry:

```lisp
(history-kit:history-merge (history-kit:make-history) :nope)
;; => TYPE-ERROR
```

## Unknown search modes

The mode dispatch is an `ecase`, so an unrecognised mode signals a
`case-failure` (a subtype of `type-error` on most implementations) rather than
silently falling back to a default:

```lisp
(history-kit:history-search *history* "git" :mode :fuzzy)
;; => error: :FUZZY fell through ECASE expression
```

## What is *not* an error

These are ordinary results, not conditions:

| Situation | Result |
| --- | --- |
| Search matches nothing | `nil` (the empty list) |
| `history-previous` with no older match | `nil`, cursor unchanged |
| `history-previous` on an empty store | `nil`, no walk started |
| `history-next` with no walk in progress | `nil` |
| `history-delete` matching nothing | `0` |
| `history-entry-line-suffix` with no match | `nil` |
| Recording into a zero-capacity store | The entry is dropped |

The consistent use of `nil` for "nothing happened" is what lets a key handler
be written as `(or (history-previous ...) buffer)` — see
[Recall Navigation](../guide/navigation.md).

!!! note "`nil` versus `\"\"` in `history-entry-line-suffix`"

    `history-entry-line-suffix` is the one place where an empty string and
    `nil` mean different things: `nil` is "no line matched" and `""` is "a line
    is exactly the query, so there is nothing left to suggest". See
    [Search](../guide/search.md).

## Guarding untrusted input

The store's `capacity` is the resource bound: it is finite by default (10,000
entries) and cannot be exceeded, so recording in a loop cannot grow the store
without limit.

There is no bound on the *length* of an individual entry's text. A host feeding
it untrusted input should impose its own limit before recording:

```lisp
(defun record-bounded (history text &key (max-length 4096))
  (history-kit:history-add
   history
   (if (<= (length text) max-length)
       text
       (subseq text 0 max-length))))
```

## Future direction

Library-specific condition types are a plausible addition once there is a
failure mode that a caller would want to handle differently from a programming
error. There is none today: every signalled condition indicates a caller bug,
and every runtime outcome is representable as a value.
