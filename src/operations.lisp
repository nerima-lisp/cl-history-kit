;;;; src/operations.lisp
;;;;
;;;; Mutating store operations.  Each one leaves the store's two invariants
;;;; intact: entries stay newest-first and within capacity, and any operation
;;;; that shifts entry positions clears the navigation cursor rather than
;;;; leaving it pointing at a different entry than the user last saw.
(in-package #:history-kit)

(defun %history-dedupe (entries)
  "Return ENTRIES with later repeats of an earlier entry's text removed.

ENTRIES is newest-first, so the surviving copy of a repeated command is always
the most recent one: re-running a command moves it to the top rather than
leaving a stale copy above it."
  (let ((seen (make-hash-table :test #'equal :size (length entries))))
    (loop for entry in entries
          for text = (%history-entry-text entry)
          unless (gethash text seen)
            do (setf (gethash text seen) t)
          and
          collect entry)))

(defun %history-find-text-offset (history text)
  "Return the newest-first offset of TEXT in HISTORY, or NIL."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
  (loop for offset below (%history-count history)
        when (string= text (%history-entry-text (%history-entry-at history offset)))
          return offset))

(defun %history-add-entry (history entry duplicate-offset &key (update-revision t))
  "Record ENTRY at the logical head, removing DUPLICATE-OFFSET when supplied.

When UPDATE-REVISION is NIL, the caller is responsible for advancing HISTORY
revision after its composite operation completes."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
  (let ((capacity (%history-capacity history)))
    (unless (zerop capacity)
      (let* ((storage (%history-entries history))
             (texts (%history-texts history))
             (count (%history-count history))
             (head (mod (1- (%history-head history)) capacity)))
        (when (and (null duplicate-offset) (= count capacity))
          (remhash
           (%history-entry-text (%history-entry-at history (1- count)))
           texts))
        (when duplicate-offset
          (loop for offset from (1+ duplicate-offset) below count
                do (setf (aref storage (mod (+ head offset) capacity))
                         (%history-entry-at history offset))))
        (setf (%history-head history) head
              (aref storage head) entry
              (%history-count history) (if duplicate-offset
                                         count
                                         (min capacity (1+ count)))
              (gethash (%history-entry-text entry) texts) t)
        (when update-revision
          (incf (%history-revision history)))))
    history))

(defmacro %purging ((history entries) &body remaining-form)
  "Install a filtered snapshot unless HISTORY changed during filtering."
  (let ((remaining (gensym "REMAINING"))
        (original-count (gensym "ORIGINAL-COUNT"))
        (revision (gensym "REVISION"))
        (removed (gensym "REMOVED")))
    `(let* ((,entries (%history-entry-list ,history))
           (,original-count (%history-count ,history))
           (,revision (%history-revision ,history))
           (,remaining
          (progn
            ,@remaining-form))
           (,removed (- ,original-count (length ,remaining))))
      (unless (= (%history-revision ,history) ,revision)
        (error "History changed while a purge predicate was running."))
      (when (plusp ,removed)
        (%history-install-entries ,history ,remaining)
        (%history-reset-cursor ,history))
      ,removed)))

(define-typed-function
  history-add
  (history history text &key exit-code (timestamp (get-universal-time)))
  "Record TEXT as the newest entry of HISTORY.

Honours the configured duplicate policy, drops the oldest entries past capacity,
and resets navigation. Returns HISTORY and the entry just recorded."
  ()
  (let ((entry (make-history-entry text :timestamp timestamp :exit-code exit-code)))
    (%history-add-entry
      history
      entry
      (and
        (eq (%history-duplicate-policy history) :remove)
        (gethash text (%history-texts history))
        (%history-find-text-offset history text)))
    (%history-reset-cursor history)
    (values history entry)))

(define-typed-function
  history-clear
  (history history)
  "Remove every entry from HISTORY and reset navigation.  Returns HISTORY."
  ()
  (%history-install-entries history nil)
  (%history-reset-cursor history))

(define-typed-function
  history-delete
  (history history text &key (case-sensitive t))
  "Delete every entry of HISTORY whose text matches TEXT exactly.

Comparison is case-sensitive unless CASE-SENSITIVE is NIL.  Returns the number
of entries deleted; navigation is reset only when that count is non-zero, so a
miss leaves an in-progress recall untouched."
  ((text string))
  (%purging
    (history entries)
    (remove-if
      (lambda (entry)
        (%text-equal-p (%history-entry-text entry) text :case-sensitive case-sensitive))
      entries)))

(define-typed-function
  history-dedup
  (history history)
  "Compact HISTORY in place, removing later entries that repeat an earlier
entry's text.

This applies the same case-sensitive EQUAL comparison %HISTORY-DEDUPE uses at
add-time, keeping each distinct text's newest occurrence and dropping the
rest.  It works the same way regardless of HISTORY's :DUPLICATE-POLICY --
that policy only governs what HISTORY-ADD does going forward, whereas this is
an explicit, on-demand purge of whatever is currently stored (useful after
loading a history that was never deduplicated, e.g. from disk).  Returns the
number of entries removed; navigation is reset only when that count is
non-zero, so a no-op call leaves an in-progress recall untouched."
  ()
  (%purging (history entries) (%history-dedupe entries)))

(define-typed-function
  history-delete-if
  (history history predicate)
  "Delete every entry of HISTORY for which PREDICATE returns true.

PREDICATE is called with each history-entry object itself, not merely its
text, so callers can match on timestamp or exit-code as well -- for example
purging every failed command via HISTORY-ENTRY-EXIT-CODE, or everything
older than some universal-time via HISTORY-ENTRY-TIMESTAMP.  This is the
predicate-based counterpart to HISTORY-DELETE, which only matches by exact
text; the two stay separate functions rather than overloading one parameter
with two argument shapes.  Returns the number of entries deleted; navigation
is reset only when that count is non-zero, so a miss leaves an in-progress
recall untouched.

PREDICATE runs over an entry snapshot captured at the start of the call.  A
predicate must not mutate the same HISTORY while it is being scanned: the
operation signals an error rather than installing a stale result."
  ()
  (%purging (history entries) (remove-if predicate entries)))
