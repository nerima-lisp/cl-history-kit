;;;; src/entry.lisp
;;;;
;;;; The immutable entry value object.  An entry is created once, never
;;;; mutated, and never shallow-copied: the store only ever conses and drops
;;;; whole entries, so there is no copier and every slot is read-only.
(in-package #:history-kit)

(defstruct (history-entry
            (:constructor %make-history-entry (text timestamp exit-code))
            (:conc-name %history-entry-)
            (:copier nil))
  "One recorded line of history.

TEXT is the recorded input. TIMESTAMP is the universal time at which it was
recorded. EXIT-CODE is the exit status of the command it ran, or NIL when the
host tracks no exit status (a bare input prompt) or has not produced one yet."
  (text "" :type string :read-only t)
  (timestamp 0 :type integer :read-only t)
  (exit-code nil :type (or null integer) :read-only t))

(define-typed-function history-entry-text (entry history-entry)
    "Return a fresh copy of ENTRY text.

The entry stores text privately, so callers cannot mutate history state through
the returned string."
    ()
  (copy-seq (%history-entry-text entry)))

(define-checked-function make-history-entry (text &key (timestamp (get-universal-time)) exit-code)
    "Create an entry recording TEXT.

TIMESTAMP defaults to the current universal time; pass it explicitly to replay
a persisted entry without restamping it.  EXIT-CODE is an integer or NIL.
TEXT is copied, so a caller may keep filling an adjustable input buffer after
recording it without corrupting the entry."
    ((text string)
     (timestamp integer)
     (exit-code (or null integer)))
  (%make-history-entry (copy-seq text) timestamp exit-code))

(define-typed-reader history-entry-timestamp (entry history-entry)
  "Return the universal-time timestamp recorded in ENTRY."
  %history-entry-timestamp)

(define-typed-reader history-entry-exit-code (entry history-entry)
  "Return the process exit code recorded in ENTRY, or NIL."
  %history-entry-exit-code)

(defun history-entry-texts (entries)
  "Return the recorded text of each entry in ENTRIES, in order."
  (mapcar #'history-entry-text entries))
