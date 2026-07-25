;;;; src/search.lisp
;;;;
;;;; Read-only queries over a store.  The four match modes share one dispatch
;;;; table, so a mode is either supported everywhere a mode is accepted or
;;;; nowhere -- there is no per-entry-point subset to keep in sync.
(in-package #:history-kit)

(defun %history-matcher (mode)
  "Return the text predicate implementing MODE."
  (ecase mode
    (:prefix #'%text-prefix-p)
    (:exact #'%text-equal-p)
    (:contains #'%text-contains-p)
    (:line-prefix #'%text-line-prefix-p)))

(defun history-entry-match-p (entry query &key (mode :prefix) case-sensitive)
  "True when ENTRY matches QUERY under MODE.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX, the last of
which matches when any line of a multi-line entry begins with QUERY."
  (check-type entry history-entry)
  (check-type query string)
  (funcall (%history-matcher mode) (history-entry-text entry) query
           :case-sensitive case-sensitive))

(defun history-entry-line-suffix (entry query &key case-sensitive)
  "Return the rest of the first line of ENTRY that begins with QUERY, or NIL.

This is the text an autosuggestion would append to what the user has typed so
far.  A line consisting of QUERY exactly yields the empty string, which is
distinguishable from the NIL returned when nothing matched."
  (check-type entry history-entry)
  (check-type query string)
  (%text-line-suffix (history-entry-text entry) query
                     :case-sensitive case-sensitive))

(defun history-search (history query &key (mode :prefix) case-sensitive (smartcase t))
  "Return the entries of HISTORY matching QUERY under MODE, newest first.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX.

SMARTCASE defaults to T and derives case sensitivity from QUERY itself -- an
all-lower-case query matches loosely, one containing an upper-case character
matches exactly -- which overrides CASE-SENSITIVE.  Pass :SMARTCASE NIL to
control sensitivity explicitly through CASE-SENSITIVE instead."
  (check-type history history)
  (check-type query string)
  (let ((matcher (%history-matcher mode))
        (sensitive (if smartcase (%smartcase-sensitive-p query) case-sensitive)))
    (remove-if-not (lambda (entry)
                     (funcall matcher (history-entry-text entry) query
                              :case-sensitive sensitive))
                   (%history-entries history))))
