;;;; t/package.lisp
(defpackage #:cl-history-kit/test
  (:use #:cl #:history-kit)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.  Nothing
  ;; else needs shadowing: every public name in HISTORY-KIT is HISTORY-
  ;; prefixed, so SEARCH, DELETE, MERGE and friends remain CL's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
   ;; Registration and assertions
   #:it #:it-each #:it-property #:it-fuzz
   #:expect #:signals #:run-all
   ;; Custom matcher definition
   #:defmatcher
   ;; Property generators
   #:gen-integer #:gen-string #:gen-list #:gen-member)
  (:export #:run-tests))

(in-package #:cl-history-kit/test)

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP fails.
Every spec gets a 10-second per-attempt wall-clock budget from cl-weave itself,
so a single hanging test fails with a clear timeout status instead of
depending on an external process-level timeout to notice anything is wrong."
  (unless (run-all :reporter :spec :timeout-ms 10000)
    (error "cl-history-kit test suite failed"))
  (format t "~&cl-history-kit/test: successful completion with 0 failures~%")
  t)
