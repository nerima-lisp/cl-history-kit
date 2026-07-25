# Search

```lisp
(history-kit:history-search history query
  &key (mode :prefix) case-sensitive (smartcase t) limit)
```

Returns the matching entries, newest first, as a fresh list.

## Modes

| Mode | Matches when |
| --- | --- |
| `:prefix` (default) | the entry text starts with the query |
| `:exact` | the entry text equals the query |
| `:contains` | the query occurs anywhere in the entry text |
| `:line-prefix` | **any** line of a multi-line entry starts with the query |

```lisp
(defparameter *history*
  (let ((history (history-kit:make-history)))
    (dolist (text '("git commit" "ls -la" "Git log" "git push") history)
      (history-kit:history-add history text))))
;; newest first: ("git push" "Git log" "ls -la" "git commit")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "git "))
;; => ("git push" "Git log" "git commit")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "ls -la" :mode :exact))
;; => ("ls -la")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "commit" :mode :contains))
;; => ("git commit")
```

The empty query matches every entry; a query that matches nothing returns
`nil`. An unknown mode signals the error from `ecase`.

### Multi-line entries

A recorded command can span several lines. `:line-prefix` matches when any one
of them starts with the query, which is what makes recalling a multi-line
command by its second line work:

```lisp
(defparameter *multiline*
  (let ((history (history-kit:make-history)))
    (history-kit:history-add history (format nil "echo one~%echo two"))
    history))

(history-kit:history-search *multiline* "echo two" :mode :line-prefix)
;; => (#<entry "echo one\necho two">)

(history-kit:history-search *multiline* "echo two")   ; :prefix
;; => NIL
```

[Recall navigation](navigation.md) uses `:line-prefix` matching internally for
exactly this reason.

## Smartcase

`smartcase` defaults to true and derives case sensitivity from the query
itself:

- an all-lower-case query matches **loosely** (case-insensitively);
- a query containing an upper-case character matches **exactly**.

This is the familiar Vim/fish convention: typing in lower case searches
loosely, and reaching for the shift key is taken as an explicit request for
precision.

```lisp
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))     ; loose
;; => ("git push" "Git log" "git commit")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "Git"))     ; exact
;; => ("Git log")
```

!!! warning "Smartcase overrides `:case-sensitive`"

    While `smartcase` is on, `case-sensitive` is ignored. Pass
    `:smartcase nil` to control sensitivity explicitly:

    ```lisp
    (history-kit:history-entry-texts
     (history-kit:history-search *history* "git"
                                 :smartcase nil :case-sensitive t))
    ;; => ("git push" "git commit")     -- "Git log" excluded

    (history-kit:history-entry-texts
     (history-kit:history-search *history* "GIT"
                                 :smartcase nil :case-sensitive nil))
    ;; => ("git push" "Git log" "git commit")
    ```

## Limiting results

`limit`, when non-`nil`, caps the result to at most that many of the newest
matches:

```lisp
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git" :limit 2))
;; => ("git push" "Git log")
```

The default, `nil`, returns every match. `limit` must be a non-negative
integer or `nil`; anything else signals a `type-error`.

## Matching a single entry

```lisp
(history-kit:history-entry-match-p entry query &key (mode :prefix) case-sensitive)
```

The same four modes, applied to one entry, returning `t` or `nil`. There is no
`smartcase` option here: this is the primitive, so the caller decides
sensitivity outright.

```lisp
(let ((entry (history-kit:make-history-entry "git commit -m x")))
  (list (history-kit:history-entry-match-p entry "git")
        (history-kit:history-entry-match-p entry "commit" :mode :contains)
        (history-kit:history-entry-match-p entry "git" :mode :exact)))
;; => (T T NIL)
```

## Autosuggestion

```lisp
(history-kit:history-entry-line-suffix entry query &key case-sensitive)
```

Returns the remainder of the first line of the entry that begins with the query
— the text an autosuggestion would append to what the user has typed so far.

```lisp
(history-kit:history-entry-line-suffix
 (history-kit:make-history-entry "git commit") "git ")
;; => "commit"
```

Two results are deliberately distinguishable:

| Result | Meaning |
| --- | --- |
| `nil` | No line matched — there is nothing to suggest |
| `""` | A line *is* the query exactly — the input is already complete |

```lisp
(let ((entry (history-kit:make-history-entry "ls")))
  (list (history-kit:history-entry-line-suffix entry "ls")    ; => ""
        (history-kit:history-entry-line-suffix entry "cd")))  ; => NIL
```

A renderer that treated both as "nothing" would be correct by accident; one
that draws a ghost suffix needs to tell them apart to avoid flickering an empty
suggestion.

Combining the two, an autosuggestion is a search plus a suffix read:

```lisp
(defun suggest (history input)
  "Return the ghost text to draw after INPUT, or NIL."
  (let ((match (first (history-kit:history-search history input))))
    (when match
      (let ((suffix (history-kit:history-entry-line-suffix match input)))
        (when (and suffix (plusp (length suffix)))
          suffix)))))
```
