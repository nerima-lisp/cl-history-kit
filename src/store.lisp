;;;; src/store.lisp
;;;;
;;;; The store: a capacity-bounded, newest-first list of entries plus the
;;;; transient cursor that navigation walks.  The struct is opaque -- its slots
;;;; live behind a private %HISTORY- conc-name and callers reach them through
;;;; the checked readers below -- so the cursor invariants in navigation.lisp
;;;; cannot be broken from outside the library.
(in-package #:history-kit)

(defstruct (history
    (:constructor %make-history (entries capacity duplicate-policy))
    (:conc-name %history-)
    (:copier nil)) "A bounded command history backed by a newest-first logical ring."
  (entries (make-array 0) :type vector)
  (head 0 :type (integer 0 *))
  (count 0 :type (integer 0 *))
  (revision 0 :type (integer 0 *))
  (capacity 10000 :type (integer 0 *) :read-only t)
  (texts (make-hash-table :test #'equal) :type hash-table :read-only t)
  (duplicate-policy :remove :type (member :remove :keep) :read-only t)
  (cursor -1 :type (integer -1 *))
  (cursor-matches nil :type (or null vector))
  (cursor-origin nil :type (or null string))
  (cursor-wrap nil :type boolean))

(define-checked-function
  make-history
  (&key (capacity 10000) (duplicate-policy :remove))
  "Create an empty history retaining at most CAPACITY entries.\n\nDUPLICATE-POLICY decides what happens when recorded text repeats an entry that\nis already stored:\n\n- :REMOVE (default) drops the older copy, so a repeated command moves to the\n  top of the history instead of accumulating stale duplicates.\n- :KEEP records every entry verbatim, preserving an exact chronological log."
  ((capacity (integer 0 *)) (duplicate-policy (member :remove :keep)))
  (%make-history (make-array capacity) capacity duplicate-policy))

(define-typed-function
  history-entries
  (history history)
  "Return the entries of HISTORY, newest first, as a fresh list."
  ()
  (%history-entry-list history))

(define-typed-function
  history-capacity
  (history history)
  "Return the maximum number of entries HISTORY retains."
  ()
  (%history-capacity history))

(define-typed-function
  history-duplicate-policy
  (history history)
  "Return the duplicate policy of HISTORY: :REMOVE or :KEEP."
  ()
  (%history-duplicate-policy history))

(define-typed-function
  history-count
  (history history)
  "Return the number of entries currently stored in HISTORY."
  ()
  (%history-count history))

(define-typed-function
  history-empty-p
  (history history)
  "True when HISTORY holds no entries."
  ()
  (zerop (%history-count history)))

(defun %history-entry-at (history offset)
  "Return the entry at logical newest-first OFFSET without allocating."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0))
           (type (integer 0 *) offset))
  (let ((capacity (%history-capacity history)))
    (aref
      (%history-entries history)
      (mod (+ (%history-head history) offset) capacity))))

(defun %history-entry-list (history)
  "Materialize HISTORY in newest-first order for snapshot-oriented operations."
  (loop for offset below (%history-count history)
        collect (%history-entry-at history offset)))

(defun %history-install-entries (history entries)
  "Replace HISTORY from newest-first ENTRIES, retaining at most its capacity."
  (let ((storage (%history-entries history))
        (texts (%history-texts history))
        (capacity (%history-capacity history))
        (count 0))
    (fill storage nil)
    (clrhash texts)
    (setf (%history-head history) 0)
    (dolist (entry entries)
      (when (= count capacity)
        (return))
      (setf (aref storage count) entry
            (gethash (%history-entry-text entry) texts) t)
      (incf count))
    (setf (%history-count history) count)
    (incf (%history-revision history)))
  history)

(defun %history-reset-cursor (history)
  "Clear the transient navigation cursor of HISTORY."
  (setf (%history-cursor history) -1
        (%history-cursor-matches history) nil
        (%history-cursor-origin history) nil
        (%history-cursor-wrap history) nil)
  history)
