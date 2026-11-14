;;;; src/access.lisp

(in-package #:history-kit)

(define-typed-function
  history-entry-at
  (history history index)
  "Return the entry at newest-first INDEX of HISTORY, or NIL past the end.

INDEX 0 is the newest entry.  The lookup allocates nothing, so a host can page
through a large history per keystroke without materializing it."
  ((index (integer 0 *)))
  (and (< index (%history-count history))
       (%history-entry-at history index)))

(define-typed-function
  history-newest
  (history history)
  "Return the newest entry of HISTORY, or NIL when it is empty."
  ()
  (and (plusp (%history-count history))
       (%history-entry-at history 0)))

(defun %history-check-revision (history revision)
  "Signal an error unless HISTORY is still at REVISION."
  (unless (= (%history-revision history) revision)
    (error "History changed while MAP-HISTORY was walking it.")))

(define-checked-function
  map-history
  (function history &key filter limit)
  "Call FUNCTION with each entry of HISTORY, newest first.  Returns NIL.

FILTER, when non-NIL, is a predicate on the entry; entries for which it returns
false are skipped and do not count toward LIMIT.  LIMIT, when non-NIL, stops
the walk after FUNCTION has been called that many times.  The walk itself
allocates nothing, so its cost is whatever FUNCTION and FILTER allocate.

FUNCTION may end the walk early with a non-local exit such as RETURN-FROM or
THROW.  Neither FUNCTION nor FILTER may modify HISTORY: the walk reads the
live store rather than a snapshot, so it signals an error instead of visiting
entries from a changed history."
  ((function (or function symbol))
   (history history)
   (filter (or function symbol))
   (limit (or null (integer 0 *))))
  (locally
    (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
    (let ((revision (%history-revision history))
          (remaining limit))
      (dotimes (offset (%history-count history))
        (when (eql remaining 0)
          (return))
        (%history-check-revision history revision)
        (let ((entry (%history-entry-at history offset)))
          (when (or (null filter) (funcall filter entry))
            (%history-check-revision history revision)
            (funcall function entry)
            (when remaining
              (decf remaining)))))
      (%history-check-revision history revision)
      nil)))
