;;;; coverage.lisp
;;;;
;;;; Coverage report: instrument src/ with sb-cover via cl-weave's
;;;; COVERAGE-STATISTICS / SAVE-COVERAGE-REPORT, run the suite once
;;;; instrumented, print an expression/branch summary, and write an HTML
;;;; report. Takes one argument, the output directory.
;;;;
;;;; See docs/src/contributing.md's "Coverage" section for why the raw
;;;; expression percentage never reaches 100 (IN-PACKAGE forms, DEFSTRUCT
;;;; slot options, and DEFMACRO bodies are not independently steppable) while
;;;; every behavioral branch is nonetheless covered.

(require :asdf)
(require :sb-cover)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults (or *load-truename*
                               *compile-file-truename*
                               (error "Unable to determine the script location"))))

(defun configure-local-source-registry (root)
  (asdf:initialize-source-registry
   `(:source-registry
     (:tree ,root)
     :inherit-configuration)))

(let* ((root (script-directory))
       (out-dir (or (second sb-ext:*posix-argv*)
                    (error "usage: sbcl --script coverage.lisp OUTPUT-DIRECTORY")))
       ;; UIOP:ENSURE-DIRECTORY-PATHNAME first: ENSURE-DIRECTORIES-EXIST reads
       ;; a pathname with no trailing slash as naming a *file*, so it would
       ;; create OUT-DIR's parents but not OUT-DIR itself, and the TRUENAME
       ;; below would then fail on the very invocation the docs suggest
       ;; ("sbcl --script coverage.lisp /tmp/cl-history-kit-coverage").
       (report-dir (merge-pathnames
                    "coverage/"
                    (truename (ensure-directories-exist
                               (uiop:ensure-directory-pathname out-dir))))))
  (configure-local-source-registry root)
  (let ((src-dir (merge-pathnames #P"src/" (asdf:system-source-directory "cl-history-kit"))))
    ;; Instrument cl-history-kit only: proclaim, force-recompile the library,
    ;; then drop instrumentation so the test system and cl-weave itself stay
    ;; uninstrumented.
    (proclaim '(optimize sb-cover:store-coverage-data))
    (asdf:load-system "cl-history-kit" :force t)
    (proclaim '(optimize (sb-cover:store-coverage-data 0)))
    (asdf:load-system "cl-history-kit/test")
    (unless (funcall (find-symbol "RUN-TESTS" "CL-HISTORY-KIT/TEST"))
      (error "cl-history-kit test suite failed"))
    (let* ((stats (funcall (find-symbol "COVERAGE-STATISTICS" "CL-WEAVE")
                            :include-pathnames (list src-dir)))
           (expression-covered (getf stats :expression-covered))
           (expression-total (getf stats :expression-total))
           (branch-covered (getf stats :branch-covered))
           (branch-total (getf stats :branch-total)))
      (format t "~&==== cl-history-kit coverage (src/ only) ====~%")
      (format t "expression: ~D/~D (~,2F%)~%"
              expression-covered expression-total
              (if (zerop expression-total) 100.0 (* 100.0 (/ expression-covered expression-total))))
      (format t "branch:     ~D/~D (~,2F%)~%"
              branch-covered branch-total
              (if (zerop branch-total) 100.0 (* 100.0 (/ branch-covered branch-total)))))
    (ensure-directories-exist report-dir)
    (funcall (find-symbol "SAVE-COVERAGE-REPORT" "CL-WEAVE")
             (namestring report-dir)
             :include-pathnames (list src-dir))
    (format t "report: ~A~%" report-dir))
  (uiop:quit 0))
