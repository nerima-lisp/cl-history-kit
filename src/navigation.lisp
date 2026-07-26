;;;; src/navigation.lisp
;;;;
;;;; The recall cursor -- what an Up/Down key pair drives.
;;;;
;;;; Three details separate this from "index into a list", and each is why the
;;;; hosts that hand-rolled it kept getting it subtly wrong:
;;;;
;;;;   * The filter is frozen at the moment navigation begins.  Typing "git "
;;;;     and pressing Up walks only the entries starting with "git ", and keeps
;;;;     walking those even though the buffer now shows a recalled command that
;;;;     no longer resembles the original prefix.
;;;;   * The in-progress input is preserved as the origin.  Walking forward off
;;;;     the newest match hands back exactly what the user had typed, rather
;;;;     than an empty buffer -- so an accidental Up is free to undo.
;;;;   * The match mode is frozen alongside the filter.  A plain Up/Down pair
;;;;     wants :LINE-PREFIX, but a Ctrl-R-style incremental search wants
;;;;     :CONTAINS over the same cursor mechanics -- HISTORY-SEARCH's matcher
;;;;     dispatch (%HISTORY-MATCHER) is reused here rather than duplicated, so
;;;;     the two never drift apart on what a mode means.
(in-package #:history-kit)

(defun %navigation-match-p (matcher text prefix sensitive)
  "True when TEXT is a navigation match for PREFIX under MATCHER, a text
predicate returned by %HISTORY-MATCHER, using the case sensitivity SENSITIVE
decided once at walk-start (see HISTORY-PREVIOUS).

An empty PREFIX matches everything under :PREFIX, :CONTAINS, and
:LINE-PREFIX, but only an exactly-empty entry under :EXACT."
  (funcall matcher text prefix :case-sensitive sensitive))

(defun %find-older-match (entries start prefix matcher sensitive)
  "Return the index and text of the first entry at or after START matching
PREFIX under MATCHER with case sensitivity SENSITIVE, or NIL when there is
none."
  (loop for entry in (nthcdr start entries)
        for index from start
        for text = (history-entry-text entry)
        when (%navigation-match-p matcher text prefix sensitive)
          do (return (values index text))))

(defun %find-newer-match (entries limit prefix matcher sensitive)
  "Return the index and text of the newest-but-one match: the entry with the
largest index strictly below LIMIT that matches PREFIX under MATCHER with
case sensitivity SENSITIVE, or NIL when there is none.  Stepping forward
moves one match toward the newest end, not to it.  Passing LIMIT equal to the
length of ENTRIES searches the whole list, yielding the oldest match instead
-- how HISTORY-NEXT wraps around."
  (let ((match-index nil)
        (match-text nil))
    (loop for entry in entries
          for index from 0 below limit
          for text = (history-entry-text entry)
          when (%navigation-match-p matcher text prefix sensitive)
            do (setf match-index index
                     match-text text))
    (values match-index match-text)))

(defun %history-restore-origin (history)
  "End navigation and return the preserved in-progress input, or NIL."
  (let ((origin (%history-cursor-origin history)))
    (%history-reset-cursor history)
    origin))

(defun %scan-with-wrap (wrap-p primary-scan wrap-scan on-found on-not-found)
  "Call PRIMARY-SCAN, a niladic thunk performing one navigation scan and
returning (VALUES INDEX TEXT) on a hit or (VALUES NIL NIL) on a miss. On a
hit, call ON-FOUND with the index and text and return its result. On a miss,
try WRAP-SCAN -- another such thunk -- only when WRAP-P is true, dispatching
its own result the same way; otherwise, or when WRAP-SCAN also misses, call
ON-NOT-FOUND with no arguments and return its result.

Continuation-passing turns the \"try the primary scan, and only on a miss try
the wraparound scan\" cascade -- duplicated in HISTORY-PREVIOUS and
HISTORY-NEXT, each with its own bookkeeping on success and its own fallback on
failure -- into one shared combinator instead of a repeated
MULTIPLE-VALUE-BIND/WHEN chain at each call site."
  (multiple-value-bind (index text) (funcall primary-scan)
    (if text
        (funcall on-found index text)
        (if wrap-p
            (multiple-value-bind (wrap-index wrap-text) (funcall wrap-scan)
              (if wrap-text
                  (funcall on-found wrap-index wrap-text)
                  (funcall on-not-found)))
            (funcall on-not-found)))))

(define-checked-function history-navigating-p (history)
    "True when HISTORY has an active navigation cursor."
    ((history history))
  (not (minusp (%history-cursor history))))

(define-checked-function history-previous (history current-input &key (mode :line-prefix) (wrap nil)
                                                                    case-sensitive (smartcase t))
    "Step one match further back into HISTORY and return its text, or NIL.

On the first call CURRENT-INPUT becomes both the filter for the whole walk and
the origin restored by HISTORY-NEXT, MODE becomes the match mode for the whole
walk -- one of the four modes HISTORY-SEARCH accepts, defaulting to
:LINE-PREFIX for a plain Up/Down key pair -- and WRAP decides whether the walk
wraps around at either end instead of stopping there once, defaulting to NIL
for the traditional stop-at-the-end behavior.  Case sensitivity for the whole
walk is also decided on this first call, exactly like HISTORY-SEARCH: SMARTCASE
defaults to T and derives it from CURRENT-INPUT itself, overriding
CASE-SENSITIVE; pass :SMARTCASE NIL to control it explicitly through
CASE-SENSITIVE instead.  Later calls ignore all four keyword arguments --
along with CURRENT-INPUT itself -- so the caller may pass whatever the buffer
currently shows, and whatever mode/wrap/sensitivity happen to be lying around,
without disturbing the walk.  WRAP, SMARTCASE and CASE-SENSITIVE are
generalized booleans: any non-NIL value counts as true, as everywhere else in
this library.

Returns NIL -- leaving the cursor where it was -- when no older entry
matches.  When WRAP is true and scanning finds no older match beyond the
cursor but at least one match exists anywhere in HISTORY, the walk wraps
around to the newest such match instead of stopping; with WRAP NIL (or with
no match anywhere regardless of WRAP), this returns NIL exactly as before.
An unknown MODE signals the error from %HISTORY-MATCHER's ECASE, same as
HISTORY-SEARCH."
    ((history history)
     (current-input string))
  (let* ((entries (%history-entries history))
         (cursor (%history-cursor history))
         (navigating (not (minusp cursor)))
         (prefix (if navigating
                     (or (%history-cursor-prefix history) "")
                     current-input))
         (walk-mode (if navigating (%history-cursor-mode history) mode))
         ;; WRAP, SMARTCASE and CASE-SENSITIVE are generalized booleans, as
         ;; every other flag in this library is, but the cursor slots holding
         ;; them across a walk are typed BOOLEAN -- the strict (MEMBER T NIL).
         ;; Normalize here, at the boundary between the two, so that passing a
         ;; perfectly ordinary truthy value such as 1 starts a wrapping walk
         ;; rather than signalling a type-error naming a private slot.
         (walk-wrap (if navigating (%history-cursor-wrap history) (and wrap t)))
         (sensitive (if navigating
                        (%history-cursor-sensitive history)
                        (and (if smartcase
                                 (%smartcase-sensitive-p current-input)
                                 case-sensitive)
                             t)))
         (matcher (%history-matcher walk-mode))
         (start (if navigating (1+ cursor) 0)))
    (%scan-with-wrap walk-wrap
                     (lambda () (%find-older-match entries start prefix matcher sensitive))
                     (lambda () (%find-older-match entries 0 prefix matcher sensitive))
                     (lambda (index text)
                       (unless navigating
                         (setf (%history-cursor-prefix history) current-input
                               (%history-cursor-origin history) current-input
                               (%history-cursor-mode history) walk-mode
                               (%history-cursor-wrap history) walk-wrap
                               (%history-cursor-sensitive history) sensitive))
                       (setf (%history-cursor history) index)
                       text)
                     (constantly nil))))

(define-checked-function history-next (history)
    "Step one match forward through HISTORY and return its text.

Stepping forward off the newest match ends navigation and returns the input
preserved when the walk began -- unless WRAP was true when the walk began (see
HISTORY-PREVIOUS), in which case the walk instead wraps around to the oldest
match and continues.  Returns NIL when HISTORY was not being navigated in the
first place."
    ((history history))
  (let ((cursor (%history-cursor history)))
    (if (not (minusp cursor))
        (let* ((entries (%history-entries history))
               (prefix (or (%history-cursor-prefix history) ""))
               (matcher (%history-matcher (or (%history-cursor-mode history)
                                              :line-prefix)))
               (sensitive (%history-cursor-sensitive history)))
          (%scan-with-wrap (%history-cursor-wrap history)
                           (lambda () (%find-newer-match entries cursor prefix matcher sensitive))
                           (lambda ()
                             (%find-newer-match entries (length entries) prefix matcher sensitive))
                           (lambda (index text)
                             (setf (%history-cursor history) index)
                             text)
                           (lambda () (%history-restore-origin history))))
        (%history-restore-origin history))))

(define-checked-function history-reset-navigation (history)
    "Abandon any active walk through HISTORY.  Returns HISTORY.

Call this when the recalled text has been accepted or the input abandoned, so
the next Up starts a fresh walk from the newest entry."
    ((history history))
  (%history-reset-cursor history))
