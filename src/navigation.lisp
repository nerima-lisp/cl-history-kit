;;;; src/navigation.lisp

(in-package #:history-kit)

(defun %history-navigation-matches (history prefix matcher sensitive)
  "Return HISTORY matches as a fixed-size newest-first vector."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
  (let ((matches
         (make-array (%history-count history)
                      :element-type 'history-entry
                      :fill-pointer 0)))
    (dotimes (offset (%history-count history) matches)
      (let ((entry (%history-entry-at history offset)))
        (when (funcall matcher (%history-entry-text entry) prefix :case-sensitive sensitive)
          (vector-push entry matches))))))

(defun %history-restore-origin (history)
  "End navigation and return the preserved in-progress input, or NIL."
  (let ((origin (%history-cursor-origin history)))
    (%history-reset-cursor history)
    origin))

(define-typed-function
  history-navigating-p
  (history history)
  "True when HISTORY has an active navigation cursor."
  ()
  (not (minusp (%history-cursor history))))

(defun %history-start-navigation (history current-input mode wrap case-sensitive smartcase)
  "Freeze a fresh navigation session and return its newest matching entry."
  (let* ((input-snapshot (copy-seq current-input))
         (sensitive
        (and
          (if smartcase (%smartcase-sensitive-p input-snapshot)
            case-sensitive)
          t))
         (matches
        (%history-navigation-matches
          history
          input-snapshot
          (%history-matcher mode)
          sensitive)))
    (when (plusp (length matches))
      (setf (%history-cursor-origin history) input-snapshot
            (%history-cursor-wrap history) (and wrap t)
            (%history-cursor-matches history) matches
            (%history-cursor history) 0)
      (history-entry-text (aref matches 0)))))

(defun %history-step-cached-match (history next wrap-target on-exhausted)
  "Advance to NEXT, wrap, or call ON-EXHAUSTED when no match remains."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
  (let ((matches (%history-cursor-matches history)))
    (cond
      ((<= 0 next (1- (length matches)))
       (setf (%history-cursor history) next)
       (history-entry-text (aref matches next)))
      ((%history-cursor-wrap history)
       (setf (%history-cursor history) wrap-target)
       (history-entry-text (aref matches wrap-target)))
      (t (funcall on-exhausted)))))

(define-typed-function
  history-previous
  (history
    history
    current-input
    &key
    (mode :line-prefix)
    (wrap nil)
    case-sensitive
    (smartcase t))
  "Step backward through the frozen matching candidates and return text."
  ((current-input string))
  (let ((cursor (%history-cursor history)))
    (if (minusp cursor) (%history-start-navigation
        history
        current-input
        mode
        wrap
        case-sensitive
        smartcase)
      (%history-step-cached-match history (1+ cursor) 0 (constantly nil)))))

(define-typed-function
  history-next
  (history history)
  "Step one match forward through HISTORY and return its text.

A navigation session indexes its frozen candidate vector in reverse. Walking
past the newest match restores the preserved origin unless wrapping was enabled
when HISTORY-PREVIOUS started the session."
  ()
  (let ((cursor (%history-cursor history)))
    (unless (minusp cursor)
      (%history-step-cached-match
        history (1- cursor) (1- (length (%history-cursor-matches history)))
        (lambda () (%history-restore-origin history))))))

(define-typed-function
  history-reset-navigation
  (history history)
  "Abandon any active walk through HISTORY.  Returns HISTORY.

Call this when the recalled text has been accepted or the input abandoned, so
the next Up starts a fresh walk from the newest entry."
  ()
  (%history-reset-cursor history))
