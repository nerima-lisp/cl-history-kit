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
  (capacity 10000 :type (integer 0 *) :read-only t)
  (duplicate-policy :remove :type (member :remove :keep) :read-only t)
  ;; Navigation cursor.  -1 means "not navigating".  CURSOR-PREFIX is the
  ;; filter frozen when navigation began, and CURSOR-ORIGIN the in-progress
  ;; input to hand back when the user walks forward past the newest match.
  (cursor -1 :type integer)
  (cursor-prefix nil :type (or null string))
  (cursor-origin nil :type (or null string)))

(defun make-history (&key (capacity 10000) (duplicate-policy :remove))
  "Create an empty history retaining at most CAPACITY entries.

DUPLICATE-POLICY decides what happens when recorded text repeats an entry that
is already stored:

- :REMOVE (default) drops the older copy, so a repeated command moves to the
  top of the list instead of accumulating stale duplicates below it.
- :KEEP records every entry verbatim, preserving an exact chronological log."
  (check-type capacity (integer 0 *))
  (check-type duplicate-policy (member :remove :keep))
  (%make-history capacity duplicate-policy))

(defun history-entries (history)
  "Return the entries of HISTORY, newest first, as a fresh list."
  (check-type history history)
  (copy-list (%history-entries history)))

(defun history-capacity (history)
  "Return the maximum number of entries HISTORY retains."
  (check-type history history)
  (%history-capacity history))

(defun history-duplicate-policy (history)
  "Return the duplicate policy of HISTORY: :REMOVE or :KEEP."
  (check-type history history)
  (%history-duplicate-policy history))

(defun history-count (history)
  "Return the number of entries currently stored in HISTORY."
  (check-type history history)
  (length (%history-entries history)))

(defun history-empty-p (history)
  "True when HISTORY holds no entries."
  (check-type history history)
  (null (%history-entries history)))

(defun %history-cap (history entries)
  "Return ENTRIES truncated to the capacity of HISTORY, dropping the oldest."
  (let ((capacity (%history-capacity history)))
    (if (<= (length entries) capacity)
        entries
        (subseq entries 0 capacity))))

(defun %history-install-entries (history entries)
  "Replace the entries of HISTORY with ENTRIES, capped to its capacity."
  (setf (%history-entries history) (%history-cap history entries))
  history)

(defun %history-reset-cursor (history)
  "Clear the transient navigation cursor of HISTORY."
  (setf (%history-cursor history) -1
        (%history-cursor-prefix history) nil
        (%history-cursor-origin history) nil)
  history)
