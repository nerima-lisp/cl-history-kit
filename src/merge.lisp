;;;; src/merge.lisp
;;;;
;;;; Combining two histories into one.  Unlike operations.lisp's other
;;;; mutations, a merge has a second history's worth of entries to fold in
;;;; against TARGET's own capacity and duplicate policy, which is enough
;;;; shape of its own (a source-list-or-history normalizer, a capacity-bounded
;;;; scan) to warrant living apart from the single-entry operations.
(in-package #:history-kit)

(defun %history-source-entries (source)
  "Return SOURCE as a newest-first entry list, or signal a type error."
  (cond
    ((history-p source) (%history-entry-list source))
    ((listp source) source)
    (t
      (error 'type-error :datum source :expected-type '(or history list)))))

(defun %history-bounded-merge-entries (target new-entries)
  "Return the capacity-bounded merge of NEW-ENTRIES and TARGET entries.

The result retains newest-first order, keeping the first occurrence of each
entry text while scanning NEW-ENTRIES then TARGET's own entries. Called only
for a :REMOVE-policy TARGET -- HISTORY-MERGE routes :KEEP targets through
%HISTORY-ADD-ENTRY instead, so deduplication here is unconditional."
  (let ((capacity (%history-capacity target))
        (target-entries (%history-entry-list target)))
    (unless (zerop capacity)
      (let ((seen (make-hash-table :test #'equal :size capacity))
            (result nil)
            (count 0))
        (loop
          for source-entries in (list new-entries target-entries)
          while (< count capacity)
          do (loop
               for entry in source-entries
               while (< count capacity)
               for text = (%history-entry-text entry)
               do (unless (gethash text seen)
                    (setf (gethash text seen) t)
                    (push entry result)
                    (incf count))))
        (nreverse result)))))

(define-typed-function
  history-merge
  (target history source)
  "Merge SOURCE into TARGET, retaining SOURCE entries first.

The target capacity and duplicate policy determine which entries remain."
  ()
  (let ((new-entries (%history-source-entries source)))
    (dolist (entry new-entries)
      (check-type entry history-entry))
    (when new-entries
      (if (eq (%history-duplicate-policy target) :keep)
          (progn
            (dolist (entry (reverse new-entries))
              (%history-add-entry target entry nil :update-revision nil))
            (incf (%history-revision target)))
          (%history-install-entries
           target
           (%history-bounded-merge-entries target new-entries)))
      (%history-reset-cursor target)))
  target)
