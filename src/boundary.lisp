;;;; src/boundary.lisp
;;;;
;;;; Argument validation as data.  Every public entry point in this library
;;;; begins by checking its own arguments (see CONTRIBUTING.md's "validate at
;;;; the boundary"), which used to mean the same CHECK-TYPE calls, imperative
;;;; and interleaved with a docstring, repeated at the top of some twenty
;;;; functions.  DEFINE-CHECKED-FUNCTION lifts that repetition out of the
;;;; imperative body and into a declarative CHECKS list -- what is validated
;;;; is now data the definition carries, not logic it performs -- so a reader
;;;; (or a future macro walking the source) can see a function's contract
;;;; without reading its body, and the CHECK-TYPE/DEFUN wiring itself has
;;;; exactly one definition instead of one per call site.
(in-package #:history-kit)

(defmacro define-checked-function (name lambda-list documentation (&rest checks) &body body)
  "Define NAME as an ordinary function, exactly as DEFUN LAMBDA-LIST
DOCUMENTATION BODY would, except the boundary validation that would otherwise
open BODY is supplied separately as CHECKS: a list of (VAR TYPE) pairs, each
compiled to (CHECK-TYPE VAR TYPE) and run, in order, before BODY.

DOCUMENTATION is mandatory -- every public entry point in HISTORY-KIT
documents its contract -- so this macro also enforces that convention
structurally rather than leaving it to review.

NAME remains an ordinary function: it can be FUNCALLed, APPLYed, or passed as
a #'NAME first-class value like any DEFUN, which is why this macro wraps
DEFUN rather than replacing the definitions it generates with macros of their
own -- a macro cannot stand in for a function at those call sites."
  `(defun ,name ,lambda-list
     ,documentation
     ,@(mapcar (lambda (check) `(check-type ,(first check) ,(second check))) checks)
     ,@body))
