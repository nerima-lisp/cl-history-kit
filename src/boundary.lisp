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
;;;; exactly one definition instead of one per call site.  DEFINE-TYPED-
;;;; FUNCTION below builds on it for the common further case: nearly every
;;;; checked function's first CHECKS entry validates its own principal
;;;; argument (a HISTORY or a HISTORY-ENTRY), so that shared entry becomes
;;;; data this macro supplies once rather than a literal each call site
;;;; repeats.  DEFINE-TYPED-READER builds on THAT for the narrower case of a
;;;; checked reader whose entire body is one forwarding call.
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

(defmacro define-typed-function
    (name (var type &rest extra-args) documentation (&rest extra-checks) &body body)
  "Define NAME as a DEFINE-CHECKED-FUNCTION whose first parameter VAR is
checked against TYPE ahead of EXTRA-CHECKS, over the lambda list (VAR
. EXTRA-ARGS).

Nearly every checked function in this library takes a principal argument --
a HISTORY or a HISTORY-ENTRY -- and validates it first; only the two
constructors (MAKE-HISTORY, MAKE-HISTORY-ENTRY) do not, since they have no
existing instance to receive. This macro lifts that one shared position out
of each call site's CHECKS list, the same way DEFINE-CHECKED-FUNCTION itself
lifted CHECK-TYPE out of each function's body."
  `(define-checked-function ,name (,var ,@extra-args) ,documentation
       ((,var ,type) ,@extra-checks)
     ,@body))

(defmacro define-typed-reader (name (var type) documentation accessor)
  "Define NAME as a DEFINE-TYPED-FUNCTION of VAR alone, whose entire BODY is
the single call (ACCESSOR VAR).

Six checked readers in this library -- three of HISTORY-ENTRY's slots, three
of HISTORY's -- do nothing beyond that one forwarding call to a private
accessor (or, for HISTORY-ENTRIES, to another internal function of the same
one-argument shape). ACCESSOR is data here the same way CHECKS already is in
DEFINE-CHECKED-FUNCTION: this macro exists only for that exact shape, so a
reader that does anything else -- HISTORY-EMPTY-P computes ZEROP over a
count, HISTORY-ENTRY-TEXT copies its result -- stays a DEFINE-TYPED-FUNCTION
with its own body rather than being forced to fit here."
  `(define-typed-function ,name (,var ,type) ,documentation ()
     (,accessor ,var)))
