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
          for text = (history-entry-text entry)
          unless (gethash text seen)
            do (setf (gethash text seen) t)
            and collect entry)))

(defun %history-remove-text (entries text)
  "Return ENTRIES with any entry whose text is STRING= to TEXT removed.

This is HISTORY-ADD's :REMOVE-policy displacement step, not a general
dedupe: under that policy ENTRIES is already duplicate-free by induction (it
only ever grows through this same step), so the entry just recorded has at
most one existing entry to displace. A single linear scan comparing TEXT
therefore gives the same result as running the newly-consed list through
%HISTORY-DEDUPE's hash-table rebuild, without allocating or hashing into a
table sized for the whole history on every recorded entry."
  (remove text entries :key #'history-entry-text :test #'string=))

(defmacro %purging ((history entries) &body remaining-form)
  "Evaluate REMAINING-FORM -- an expression computing the surviving subset of
ENTRIES, a symbol this macro binds to HISTORY's current entries -- and, when
it dropped at least one entry, install the survivors into HISTORY and reset
its navigation cursor. Expands to the number of entries removed.

This is the shared install-if-changed protocol behind every purge in this
file that reports how many entries went: HISTORY-DELETE (exact text),
HISTORY-DEDUP (repeated text), and HISTORY-DELETE-IF (predicate). Naming the
binding ENTRIES instead of gensym-ing it is deliberate anaphoric-macro style
(compare ON LISP's AIF/IT): every call site below reads ENTRIES from
REMAINING-FORM, so capturing that name on purpose -- not hiding it -- is the
whole point."
  (let ((remaining (gensym "REMAINING"))
        (removed (gensym "REMOVED")))
    `(let* ((,entries (%history-entries ,history))
            (,remaining (progn ,@remaining-form))
            (,removed (- (length ,entries) (length ,remaining))))
       (when (plusp ,removed)
         (%history-install-entries ,history ,remaining)
         (%history-reset-cursor ,history))
       ,removed)))

(define-checked-function history-add (history text &key exit-code (timestamp (get-universal-time)))
    "Record TEXT as the newest entry of HISTORY.

Honours the store's duplicate policy, drops the oldest entries past capacity,
and resets navigation -- adding an entry shifts every index, so a cursor left
over from before the addition would silently point somewhere else.

Returns two values: HISTORY and the entry just recorded."
    ((history history))
  (let* ((entry (make-history-entry text :timestamp timestamp :exit-code exit-code))
         (old-entries (%history-entries history))
         (entries (cons entry
                        (if (eq (%history-duplicate-policy history) :remove)
                            (%history-remove-text old-entries text)
                            old-entries))))
    (%history-install-entries history entries)
    (%history-reset-cursor history)
    (values history entry)))

(define-checked-function history-clear (history)
    "Remove every entry from HISTORY and reset navigation.  Returns HISTORY."
    ((history history))
  (%history-install-entries history nil)
  (%history-reset-cursor history))

(define-checked-function history-delete (history text &key (case-sensitive t))
    "Delete every entry of HISTORY whose text matches TEXT exactly.

Comparison is case-sensitive unless CASE-SENSITIVE is NIL.  Returns the number
of entries deleted; navigation is reset only when that count is non-zero, so a
miss leaves an in-progress recall untouched."
    ((history history)
     (text string))
  (%purging (history entries)
    (remove-if (lambda (entry)
                 (%text-equal-p (history-entry-text entry) text
                                :case-sensitive case-sensitive))
               entries)))

(define-checked-function history-dedup (history)
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
    ((history history))
  (%purging (history entries)
    (%history-dedupe entries)))

(define-checked-function history-delete-if (history predicate)
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

PREDICATE runs over a snapshot of HISTORY's entries taken at the start of the
call; if it reentrantly mutates the same HISTORY (for example by calling
HISTORY-ADD) while being scanned, those in-flight changes are overwritten when
HISTORY-DELETE-IF installs its own result."
    ((history history))
  (%purging (history entries)
    (remove-if predicate entries)))

(defun %history-source-entries (source)
  "Return the entry list of SOURCE, which is a history or a list of entries."
  (cond
    ((history-p source) (%history-entries source))
    ((listp source) source)
    (t (error 'type-error :datum source :expected-type '(or history list)))))

(define-checked-function history-merge (target source)
    "Merge SOURCE into TARGET, newest-first order and duplicate policy preserved.

SOURCE is a history or a newest-first list of entries.  Each entry keeps its
original timestamp and exit code, so merging a history loaded from disk does
not restamp every entry with the load time.  Returns TARGET.

Prepends SOURCE's entries in front of TARGET's in one batch -- rather than
calling HISTORY-ADD once per entry -- and applies TARGET's duplicate policy
and capacity to the combined list a single time. This is equivalent to the
call-HISTORY-ADD-per-entry approach it replaces: repeatedly displacing a same-
text entry as each new entry is inserted at the front produces the same
survivors, in the same order, as running the whole concatenation through
%HISTORY-DEDUPE once (both keep, for each distinct text, whichever occurrence
appears first in front-to-back order); and repeatedly capping to capacity
after each insertion drops the same tail entries as capping once at the end,
since nothing after the first cap ever re-enters the kept prefix. The batched
form turns an O(entry count x TARGET capacity) merge into one that is only
O(entry count + TARGET capacity), which matters when loading a large history
from disk into an already-full store."
    ((target history))
  (let ((new-entries (%history-source-entries source)))
    (dolist (entry new-entries)
      (check-type entry history-entry))
    (when new-entries
      (let ((combined (append new-entries (%history-entries target))))
        (%history-install-entries
         target
         (if (eq (%history-duplicate-policy target) :remove)
             (%history-dedupe combined)
             combined))
        (%history-reset-cursor target))))
  target)
