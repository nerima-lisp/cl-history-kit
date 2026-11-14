;;;; src/entry.lisp

(in-package #:history-kit)

(defstruct (history-entry
            (:constructor %make-history-entry
                (text timestamp exit-code &optional cwd duration-ms origin session))
            (:conc-name %history-entry-)
            (:copier nil))
  "One recorded line of history.

TEXT is the recorded input. TIMESTAMP is the universal time at which it was
recorded. EXIT-CODE is the exit status of the command it ran, or NIL when the
host tracks no exit status (a bare input prompt) or has not produced one yet.

CWD, DURATION-MS, ORIGIN, and SESSION are optional metadata the host may attach:
the working directory the command ran in, how long it ran in milliseconds, a
symbol naming where the line came from, and an identifier of the session that
recorded it.  Each is NIL when the host did not supply it."
  (text "" :type string :read-only t)
  (timestamp 0 :type integer :read-only t)
  (exit-code nil :type (or null integer) :read-only t)
  (cwd nil :type (or null string) :read-only t)
  (duration-ms nil :type (or null (integer 0 *)) :read-only t)
  (origin nil :type (or null symbol) :read-only t)
  (session nil :type (or null string) :read-only t))

(define-typed-function history-entry-text (entry history-entry)
    "Return a fresh copy of ENTRY text.

The entry stores text privately, so callers cannot mutate history state through
the returned string."
    ()
  (copy-seq (%history-entry-text entry)))

(defun %copy-optional-string (string)
  "Return a fresh copy of STRING, or NIL when STRING is NIL."
  (and string (copy-seq string)))

(define-checked-function make-history-entry
    (text &key (timestamp (get-universal-time)) exit-code cwd duration-ms origin session)
    "Create an entry recording TEXT.

TIMESTAMP defaults to the current universal time; pass it explicitly to replay
a persisted entry without restamping it.  EXIT-CODE is an integer or NIL.
TEXT is copied, so a caller may keep filling an adjustable input buffer after
recording it without corrupting the entry.

CWD and SESSION are strings or NIL and are copied the same way.  DURATION-MS is
a non-negative integer or NIL.  ORIGIN is any symbol or NIL; it is stored as
given and never checked against a known set, so a record from a newer host
with an origin this library has never heard of survives unchanged and the host
decides what that origin means."
    ((text string)
     (timestamp integer)
     (exit-code (or null integer))
     (cwd (or null string))
     (duration-ms (or null (integer 0 *)))
     (origin (or null symbol))
     (session (or null string)))
  (%make-history-entry (copy-seq text) timestamp exit-code
                       (%copy-optional-string cwd) duration-ms origin
                       (%copy-optional-string session)))

(define-typed-reader history-entry-timestamp (entry history-entry)
  "Return the universal-time timestamp recorded in ENTRY."
  %history-entry-timestamp)

(define-typed-reader history-entry-exit-code (entry history-entry)
  "Return the process exit code recorded in ENTRY, or NIL."
  %history-entry-exit-code)

(define-typed-function history-entry-cwd (entry history-entry)
    "Return a fresh copy of the working directory recorded in ENTRY, or NIL."
    ()
  (%copy-optional-string (%history-entry-cwd entry)))

(define-typed-reader history-entry-duration-ms (entry history-entry)
  "Return the run time in milliseconds recorded in ENTRY, or NIL."
  %history-entry-duration-ms)

(define-typed-reader history-entry-origin (entry history-entry)
  "Return the origin symbol recorded in ENTRY, or NIL."
  %history-entry-origin)

(define-typed-function history-entry-session (entry history-entry)
    "Return a fresh copy of the session identifier recorded in ENTRY, or NIL."
    ()
  (%copy-optional-string (%history-entry-session entry)))

(defun history-entry-texts (entries)
  "Return the recorded text of each entry in ENTRIES, in order."
  (mapcar #'history-entry-text entries))

(define-typed-function history-entry-plist (entry history-entry)
    "Return ENTRY as a fresh property list a host can persist.

The list always carries :TEXT and :TIMESTAMP, followed by :EXIT-CODE, :CWD,
:DURATION-MS, :ORIGIN, and :SESSION for whichever of those are non-NIL.
Strings are fresh copies.  Writing the list anywhere is left to the host:
this library performs no file I/O."
    ()
  (let ((optional
          (loop for (key value) on (list :exit-code (%history-entry-exit-code entry)
                                         :cwd (%history-entry-cwd entry)
                                         :duration-ms (%history-entry-duration-ms entry)
                                         :origin (%history-entry-origin entry)
                                         :session (%history-entry-session entry))
                  by #'cddr
                when value
                  nconc (list key (if (stringp value) (copy-seq value) value)))))
    (list* :text (history-entry-text entry)
           :timestamp (%history-entry-timestamp entry)
           optional)))

(define-checked-function history-entry-from-plist (plist)
    "Return a new entry built from PLIST, the inverse of HISTORY-ENTRY-PLIST.

:TEXT is required and must be a string.  :TIMESTAMP defaults to 0 rather than
the current time: a persisted record that never carried a timestamp keeps an
unknown (epoch) time instead of being restamped as if recorded on load.  The
metadata keys are all optional, so a record written before they existed reads
back with NIL metadata.  Keys this library does not know are ignored, and an
origin symbol it does not know is kept as is.  A value of the wrong type
signals TYPE-ERROR; a PLIST that is not a proper list of even length signals
an error."
    ((plist list))
  (let ((length (list-length plist)))
    (unless (and length (evenp length))
      (error "History entry plist is not a proper list of even length.")))
  (make-history-entry (getf plist :text)
                      :timestamp (getf plist :timestamp 0)
                      :exit-code (getf plist :exit-code)
                      :cwd (getf plist :cwd)
                      :duration-ms (getf plist :duration-ms)
                      :origin (getf plist :origin)
                      :session (getf plist :session)))
