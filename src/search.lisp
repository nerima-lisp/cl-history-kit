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

(define-checked-function history-entry-match-p (entry query &key (mode :prefix) case-sensitive)
    "True when ENTRY matches QUERY under MODE.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX, the last of
which matches when any line of a multi-line entry begins with QUERY."
    ((entry history-entry)
     (query string))
  (funcall (%history-matcher mode) (history-entry-text entry) query
           :case-sensitive case-sensitive))

(define-checked-function history-entry-line-suffix (entry query &key case-sensitive)
    "Return the rest of the first line of ENTRY that begins with QUERY, or NIL.

This is the text an autosuggestion would append to what the user has typed so
far.  A line consisting of QUERY exactly yields the empty string, which is
distinguishable from the NIL returned when nothing matched."
    ((entry history-entry)
     (query string))
  (%text-line-suffix (history-entry-text entry) query
                     :case-sensitive case-sensitive))

(define-checked-function history-search (history query &key (mode :prefix) case-sensitive
                                         (smartcase t) limit)
    "Return the entries of HISTORY matching QUERY under MODE, newest first.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX.

SMARTCASE defaults to T and derives case sensitivity from QUERY itself -- an
all-lower-case query matches loosely, one containing an upper-case character
matches exactly -- which overrides CASE-SENSITIVE.  Pass :SMARTCASE NIL to
control sensitivity explicitly through CASE-SENSITIVE instead.

LIMIT, when non-NIL, caps the number of matches returned to at most that many
of the newest matches.  It must be a non-negative integer.  The default, NIL,
returns every match.  Passing LIMIT stops scanning HISTORY as soon as that
many matches are found instead of scanning every entry and truncating
afterward, so a small LIMIT against a large, mostly-unmatching HISTORY costs
proportionally to where the LIMITth match sits rather than to HISTORY's
total size."
    ((history history)
     (query string)
     (limit (or null (integer 0 *))))
  (let ((matcher (%history-matcher mode))
        (sensitive (if smartcase (%smartcase-sensitive-p query) case-sensitive))
        (remaining limit))
    (loop for entry in (%history-entries history)
          until (eql remaining 0)
          when (funcall matcher (history-entry-text entry) query :case-sensitive sensitive)
            collect entry into matches
            and do (when remaining (decf remaining))
          finally (return matches))))
