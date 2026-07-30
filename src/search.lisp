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

(define-typed-function
  history-entry-match-p
  (entry history-entry query &key (mode :prefix) case-sensitive)
  "True when ENTRY matches QUERY under MODE.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX, the last of
which matches when any line of a multi-line entry begins with QUERY."
  ((query string))
  (funcall
    (%history-matcher mode)
    (%history-entry-text entry)
    query
    :case-sensitive
    case-sensitive))

(define-typed-function
  history-entry-line-suffix
  (entry history-entry query &key case-sensitive)
  "Return the rest of the first line of ENTRY that begins with QUERY, or NIL.

This is the text an autosuggestion would append to what the user has typed so
far.  A line consisting of QUERY exactly yields the empty string, which is
distinguishable from the NIL returned when nothing matched."
  ((query string))
  (%text-line-suffix
    (%history-entry-text entry)
    query
    :case-sensitive
    case-sensitive))

(define-typed-function
  history-search
  (history history query &key (mode :prefix) case-sensitive (smartcase t) limit)
  "Return the entries of HISTORY matching QUERY under MODE, newest first.

MODE is :PREFIX (default), :EXACT, :CONTAINS, or :LINE-PREFIX. SMARTCASE
selects sensitivity from QUERY unless it is NIL. LIMIT bounds returned matches
and stops the scan once it has been reached."
  ((query string) (limit (or null (integer 0 *))))
  (let ((matcher (%history-matcher mode))
        (sensitive
         (if smartcase (%smartcase-sensitive-p query)
             case-sensitive))
        (remaining limit)
        (matches nil))
    (locally
      (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
      (block search
        (dotimes (offset (%history-count history))
          (when (eql remaining 0)
            (return-from search (nreverse matches)))
          (let ((entry (%history-entry-at history offset)))
            (when (funcall matcher (%history-entry-text entry) query :case-sensitive sensitive)
              (push entry matches)
              (when remaining
                (decf remaining)))))
        (nreverse matches)))))
