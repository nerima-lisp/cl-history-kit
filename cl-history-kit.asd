;;;; cl-history-kit.asd

;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version -- the
;;; file is read in whatever package happens to be current. Saying it makes
;;; the file self-contained.
(in-package #:asdf-user)

(asdf:defsystem "cl-history-kit"
  :description "Dependency-free command-history store, search, and recall navigation for Common Lisp"
  :long-description "A bounded, newest-first history of recorded input lines with
duplicate policies, four search modes with smartcase, and the prefix-filtered recall
cursor an Up/Down key pair drives -- including preservation of the in-progress input
so stepping forward past the newest match restores exactly what the user had typed."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage "https://github.com/nerima-lisp/cl-history-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-history-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-history-kit.git")
  :depends-on ()
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "boundary")
               (:file "text")
               (:file "entry")
               (:file "store")
               (:file "operations")
               (:file "merge")
               (:file "search")
               (:file "navigation"))
  :in-order-to ((test-op (test-op "cl-history-kit/test"))))

(asdf:defsystem "cl-history-kit/test"
  :description "Test system for cl-history-kit"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.1"
  :homepage "https://github.com/nerima-lisp/cl-history-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-history-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-history-kit.git")
  :depends-on ("cl-history-kit" (:version "cl-weave" "1.1.0"))
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "helpers-matchers")
               (:file "boundary-test")
               (:file "entry-test")
               (:file "store-test")
               (:file "operations-test")
               (:file "merge-test")
               (:file "search-test")
               (:file "navigation-test")
               (:file "property-test"))
  :perform (test-op (operation component) (declare (ignore operation component)) (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-HISTORY-KIT/TEST"))) (error "cl-history-kit test suite failed"))))
