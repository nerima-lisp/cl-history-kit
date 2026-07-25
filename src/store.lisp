;;;; src/store.lisp
;;;;
;;;; The store: a capacity-bounded, newest-first list of entries plus the
;;;; transient cursor that navigation walks.  The struct is opaque -- its slots
;;;; live behind a private %HISTORY- conc-name and callers reach them through
;;;; the checked readers below -- so the cursor invariants in navigation.lisp
;;;; cannot be broken from outside the library.
(in-package #:history-kit)

(defstruct (history
            (:constructor %make-history (capacity duplicate-policy))
            (:conc-name %history-)
            (:copier nil))
  "A bounded command history with a transient navigation cursor."
  ;; Recorded entries, newest first.  Never longer than CAPACITY.
  (entries nil :type list)
  ;; The length of ENTRIES, maintained by %HISTORY-INSTALL-ENTRIES -- the
  ;; single place entries are ever replaced -- so HISTORY-COUNT reads a slot
  ;; instead of walking ENTRIES with LENGTH on every call.
  (count 0 :type (integer 0 *))
  (capacity 10000 :type (integer 0 *) :read-only t)
  (duplicate-policy :remove :type (member :remove :keep) :read-only t)
  ;; Navigation cursor.  -1 means "not navigating".  CURSOR-PREFIX is the
  ;; filter frozen when navigation began, CURSOR-ORIGIN the in-progress
  ;; input to hand back when the user walks forward past the newest match,
  ;; CURSOR-MODE the match mode -- one of HISTORY-SEARCH's four -- frozen
  ;; alongside the filter, CURSOR-WRAP whether the walk wraps around at
  ;; either end instead of stopping, and CURSOR-SENSITIVE the case
  ;; sensitivity decided once from the frozen prefix (via SMARTCASE or an
  ;; explicit override) at walk-start, rather than recomputed on every step.
  (cursor -1 :type integer)
  (cursor-prefix nil :type (or null string))
  (cursor-origin nil :type (or null string))
  (cursor-mode nil :type (or null keyword))
  (cursor-wrap nil :type boolean)
  (cursor-sensitive nil :type boolean))

(define-checked-function make-history (&key (capacity 10000) (duplicate-policy :remove))
    "Create an empty history retaining at most CAPACITY entries.

DUPLICATE-POLICY decides what happens when recorded text repeats an entry that
is already stored:

- :REMOVE (default) drops the older copy, so a repeated command moves to the
  top of the list instead of accumulating stale duplicates below it.
- :KEEP records every entry verbatim, preserving an exact chronological log."
    ((capacity (integer 0 *))
     (duplicate-policy (member :remove :keep)))
  (%make-history capacity duplicate-policy))

(define-checked-function history-entries (history)
    "Return the entries of HISTORY, newest first, as a fresh list."
    ((history history))
  (copy-list (%history-entries history)))

(define-checked-function history-capacity (history)
    "Return the maximum number of entries HISTORY retains."
    ((history history))
  (%history-capacity history))

(define-checked-function history-duplicate-policy (history)
    "Return the duplicate policy of HISTORY: :REMOVE or :KEEP."
    ((history history))
  (%history-duplicate-policy history))

(define-checked-function history-count (history)
    "Return the number of entries currently stored in HISTORY."
    ((history history))
  (%history-count history))

(define-checked-function history-empty-p (history)
    "True when HISTORY holds no entries."
    ((history history))
  (null (%history-entries history)))

(defun %history-cap (history entries)
  "Return two values: ENTRIES truncated to the capacity of HISTORY (dropping
the oldest), and the length of that truncated list.

Returning the length alongside the list lets %HISTORY-INSTALL-ENTRIES cache
entry count without a second traversal of ENTRIES.

Detects whether truncation is needed with NTHCDR rather than LENGTH: NTHCDR
walks at most CAPACITY cells and stops as soon as it finds (or rules out) a
CAPACITY-plus-first entry, whereas LENGTH walks ENTRIES to its end regardless
-- costly right after HISTORY-MERGE combines a large SOURCE with an
already-full TARGET, where ENTRIES can run far longer than CAPACITY. Below
capacity, this returns ENTRIES itself with no copying, exactly as before."
  (let ((capacity (%history-capacity history)))
    (if (nthcdr capacity entries)
        (values (subseq entries 0 capacity) capacity)
        (values entries (length entries)))))

(defun %history-install-entries (history entries)
  "Replace the entries of HISTORY with ENTRIES, capped to its capacity."
  (multiple-value-bind (capped count) (%history-cap history entries)
    (setf (%history-entries history) capped
          (%history-count history) count))
  history)

(defun %history-reset-cursor (history)
  "Clear the transient navigation cursor of HISTORY."
  (setf (%history-cursor history) -1
        (%history-cursor-prefix history) nil
        (%history-cursor-origin history) nil
        (%history-cursor-mode history) nil
        (%history-cursor-wrap history) nil
        (%history-cursor-sensitive history) nil)
  history)
