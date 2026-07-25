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
  (let ((seen (make-hash-table :test #'equal)))
    (loop for entry in entries
          for text = (history-entry-text entry)
          unless (gethash text seen)
            do (setf (gethash text seen) t)
            and collect entry)))

(defun history-add (history text &key exit-code (timestamp (get-universal-time)))
  "Record TEXT as the newest entry of HISTORY.

Honours the store's duplicate policy, drops the oldest entries past capacity,
and resets navigation -- adding an entry shifts every index, so a cursor left
over from before the addition would silently point somewhere else.

Returns two values: HISTORY and the entry just recorded."
  (check-type history history)
  (let* ((entry (make-history-entry text :timestamp timestamp :exit-code exit-code))
         (entries (cons entry (%history-entries history))))
    (%history-install-entries history
                              (if (eq (%history-duplicate-policy history) :remove)
                                  (%history-dedupe entries)
                                  entries))
    (%history-reset-cursor history)
    (values history entry)))

(defun history-clear (history)
  "Remove every entry from HISTORY and reset navigation.  Returns HISTORY."
  (check-type history history)
  (%history-install-entries history nil)
  (%history-reset-cursor history))

(defun history-delete (history text &key (case-sensitive t))
  "Delete every entry of HISTORY whose text matches TEXT exactly.

Comparison is case-sensitive unless CASE-SENSITIVE is NIL.  Returns the number
of entries deleted; navigation is reset only when that count is non-zero, so a
miss leaves an in-progress recall untouched."
  (check-type history history)
  (check-type text string)
  (let* ((entries (%history-entries history))
         (remaining (remove-if (lambda (entry)
                                 (%text-equal-p (history-entry-text entry) text
                                                :case-sensitive case-sensitive))
                               entries))
         (deleted (- (length entries) (length remaining))))
    (when (plusp deleted)
      (%history-install-entries history remaining)
      (%history-reset-cursor history))
    deleted))

(defun %history-source-entries (source)
  "Return the entry list of SOURCE, which is a history or a list of entries."
  (cond
    ((history-p source) (%history-entries source))
    ((listp source) source)
    (t (error 'type-error :datum source :expected-type '(or history list)))))

(defun history-merge (target source)
  "Merge SOURCE into TARGET, newest-first order and duplicate policy preserved.

SOURCE is a history or a newest-first list of entries.  Each entry keeps its
original timestamp and exit code, so merging a history loaded from disk does
not restamp every entry with the load time.  Returns TARGET."
  (check-type target history)
  (dolist (entry (reverse (%history-source-entries source)) target)
    (check-type entry history-entry)
    (history-add target (history-entry-text entry)
                 :timestamp (history-entry-timestamp entry)
                 :exit-code (history-entry-exit-code entry))))
