# Search

```lisp
(history-kit:history-search history query
  &key (mode :prefix) case-sensitive (smartcase t) limit filter)
```

Returns the matching entries, newest first, as a fresh list.

## Modes

| Mode | Matches when |
| --- | --- |
| `:prefix` (default) | the entry text starts with the query |
| `:exact` | the entry text equals the query |
| `:contains` | the query occurs anywhere in the entry text |
| `:line-prefix` | **any** line of a multi-line entry starts with the query |
| `:fuzzy` | the query's characters appear in the entry text in order, not necessarily adjacent |

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

`history-search` with `:fuzzy` returns matches newest first like every other
mode. To rank them by match quality, use
[`history-fuzzy-search`](#fuzzy-search).

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

Case-insensitive `:contains` and `:fuzzy` matching compares two ASCII
characters by character-code arithmetic and passes any other pair to
`char-equal`. The results are identical to comparing every pair with
`char-equal`.

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

## Filtering results

`filter` is a predicate called with each `history-entry`. An entry is returned
only when it matches `mode` and `filter` returns true. Entries that `filter`
rejects do not count toward `limit`, so `:limit 1` still finds the newest entry
that passes both tests.

The predicate usually reads [entry metadata](store.md#entry-metadata). This
autosuggestion source prefers a command recorded in the current directory and
falls back to the whole history:

```lisp
(defun suggestion-source (history input cwd)
  "Return the entry to suggest from for INPUT, preferring CWD."
  (flet ((newest (&rest keys)
           (first (apply #'history-kit:history-search history input
                         :mode :line-prefix :limit 1 keys))))
    (or (newest :filter (lambda (entry)
                          (equal (history-kit:history-entry-cwd entry) cwd)))
        (newest))))
```

## Matching a single entry

```lisp
(history-kit:history-entry-match-p entry query &key (mode :prefix) case-sensitive)
```

The same modes, applied to one entry, returning `t` or `nil`. There is no
`smartcase` option here: this is the primitive, so the caller decides
sensitivity outright.

```lisp
(let ((entry (history-kit:make-history-entry "git commit -m x")))
  (list (history-kit:history-entry-match-p entry "git")
        (history-kit:history-entry-match-p entry "commit" :mode :contains)
        (history-kit:history-entry-match-p entry "git" :mode :exact)))
;; => (T T NIL)
```

## Fuzzy search

```lisp
(history-kit:history-fuzzy-search history query
  &key filter limit case-sensitive (smartcase t))
(history-kit:history-entry-fuzzy-score entry query &key case-sensitive)
```

`history-fuzzy-search` is meant for a ++ctrl+r++ picker. It keeps the entries
that `:fuzzy` matches and orders them by `history-entry-fuzzy-score`, highest
first. Entries with equal scores stay newest first. `limit` applies after
ranking, so `:limit 10` returns the ten best matches rather than the ten newest.
`filter` and smartcase behave as in `history-search`.

```lisp
(let ((history (history-kit:make-history)))
  (dolist (text '("git status" "gist show" "grep main"))
    (history-kit:history-add history text))
  (history-kit:history-entry-texts
   (history-kit:history-fuzzy-search history "gst")))
;; => "git status" and "gist show", best score first;
;;    "grep main" has no "s" after its "g", so it does not match
```

`history-entry-fuzzy-score` returns `nil` when the query is not a subsequence
of the entry text, and an integer otherwise. The score rises for runs of
consecutive matched characters and for matches at a word boundary: the start of
the text, or the character after a space, `/`, `-`, `_`, `.`, or newline. It falls
for each gap between matched characters. The scorer makes one greedy pass, so
it does not always find the best possible alignment. The exact values are not
part of the API; use a score only to compare entries against the same query.

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
