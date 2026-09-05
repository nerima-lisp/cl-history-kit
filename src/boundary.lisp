;;;; src/boundary.lisp

(in-package #:history-kit)

(defmacro define-checked-function (name lambda-list documentation (&rest checks) &body body)
  "Define a function whose CHECKS run before BODY."
  `(defun ,name ,lambda-list
     ,documentation
     ,@(mapcar (lambda (check) `(check-type ,(first check) ,(second check))) checks)
     ,@body))

(defmacro define-typed-function
    (name (var type &rest extra-args) documentation (&rest extra-checks) &body body)
  "Define a checked function whose first argument has TYPE."
  `(define-checked-function ,name (,var ,@extra-args) ,documentation
       ((,var ,type) ,@extra-checks)
     ,@body))

(defmacro define-typed-reader (name (var type) documentation accessor)
  "Define a checked reader that calls ACCESSOR with VAR."
  `(define-typed-function ,name (,var ,type) ,documentation ()
     (,accessor ,var)))
