;;;; src/navigation.lisp
;;;;
;;;; The recall cursor -- what an Up/Down key pair drives.
;;;;
;;;; Two details separate this from "index into a list", and both are why the
;;;; hosts that hand-rolled it kept getting it subtly wrong:
;;;;
;;;;   * The filter is frozen at the moment navigation begins.  Typing "git "
;;;;     and pressing Up walks only the entries starting with "git ", and keeps
;;;;     walking those even though the buffer now shows a recalled command that
;;;;     no longer resembles the original prefix.
;;;;   * The in-progress input is preserved as the origin.  Walking forward off
;;;;     the newest match hands back exactly what the user had typed, rather
;;;;     than an empty buffer -- so an accidental Up is free to undo.
(in-package #:history-kit)

(defun %navigation-match-p (text prefix)
  "True when TEXT is a navigation match for PREFIX.

Matching is line-prefix (so a multi-line entry is recalled by any of its
lines) under the smartcase rule, and an empty prefix matches everything."
  (%text-line-prefix-p text prefix
                       :case-sensitive (%smartcase-sensitive-p prefix)))

(defun %find-older-match (entries start prefix)
  "Return the index and text of the first entry at or after START matching
PREFIX, or NIL when there is none."
  (loop for entry in (nthcdr start entries)
        for index from start
        for text = (history-entry-text entry)
        when (%navigation-match-p text prefix)
          do (return (values index text))))

(defun %find-newer-match (entries limit prefix)
  "Return the index and text of the newest-but-one match: the entry with the
largest index strictly below LIMIT that matches PREFIX, or NIL when there is
none.  Stepping forward moves one match toward the newest end, not to it."
  (let ((match-index nil)
        (match-text nil))
    (loop for entry in entries
          for index from 0 below limit
          for text = (history-entry-text entry)
          when (%navigation-match-p text prefix)
            do (setf match-index index
                     match-text text))
    (values match-index match-text)))

(defun %history-restore-origin (history)
  "End navigation and return the preserved in-progress input, or NIL."
  (let ((origin (%history-cursor-origin history)))
    (%history-reset-cursor history)
    origin))

(defun history-navigating-p (history)
  "True when HISTORY has an active navigation cursor."
  (check-type history history)
  (not (minusp (%history-cursor history))))

(defun history-previous (history current-input)
  "Step one match further back into HISTORY and return its text, or NIL.

On the first call CURRENT-INPUT becomes both the filter for the whole walk and
the origin restored by HISTORY-NEXT; later calls ignore it, so the caller may
pass whatever the buffer currently shows without disturbing the walk.  Returns
NIL -- leaving the cursor where it was -- when no older entry matches."
  (check-type history history)
  (check-type current-input string)
  (let* ((entries (%history-entries history))
         (cursor (%history-cursor history))
         (navigating (not (minusp cursor)))
         (prefix (if navigating
                     (or (%history-cursor-prefix history) "")
                     current-input))
         (start (if navigating (1+ cursor) 0)))
    (multiple-value-bind (index text) (%find-older-match entries start prefix)
      (when text
        (unless navigating
          (setf (%history-cursor-prefix history) current-input
                (%history-cursor-origin history) current-input))
        (setf (%history-cursor history) index)
        text))))

(defun history-next (history)
  "Step one match forward through HISTORY and return its text.

Stepping forward off the newest match ends navigation and returns the input
preserved when the walk began.  Returns NIL when HISTORY was not being
navigated in the first place."
  (check-type history history)
  (let ((cursor (%history-cursor history)))
    (if (plusp cursor)
        (multiple-value-bind (index text)
            (%find-newer-match (%history-entries history) cursor
                               (or (%history-cursor-prefix history) ""))
          (cond
            (text
             (setf (%history-cursor history) index)
             text)
            (t (%history-restore-origin history))))
        (%history-restore-origin history))))

(defun history-reset-navigation (history)
  "Abandon any active walk through HISTORY.  Returns HISTORY.

Call this when the recalled text has been accepted or the input abandoned, so
the next Up starts a fresh walk from the newest entry."
  (check-type history history)
  (%history-reset-cursor history))
