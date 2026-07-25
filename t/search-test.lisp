;;;; t/search-test.lisp
(in-package #:cl-history-kit/test)

(defun searchable-history ()
  (history-of '("git push" "Git log" "ls -la" "git commit")))

(describe "search modes"
  (it "matches a prefix by default, newest first"
    (expect (history-search (searchable-history) "git ")
            :to-have-texts '("git push" "Git log" "git commit")))

  (it "matches whole texts under :EXACT"
    (expect (history-search (searchable-history) "ls -la" :mode :exact)
            :to-have-texts '("ls -la")))

  (it "matches anywhere under :CONTAINS"
    (expect (history-search (searchable-history) "commit" :mode :contains)
            :to-have-texts '("git commit")))

  (it "matches any line of a multi-line entry under :LINE-PREFIX"
    (let ((history (history-of (list (format nil "echo one~%echo two")))))
      (expect (history-search history "echo two" :mode :line-prefix)
              :to-have-texts (list (format nil "echo one~%echo two")))
      (expect (history-search history "echo two") :to-have-texts '())))

  (it "returns everything for the empty query and nothing for a miss"
    (expect (length (history-search (searchable-history) "")) :to-be 4)
    (expect (history-search (searchable-history) "nope") :to-have-texts '()))

  (it "rejects an unknown mode"
    (signals error (history-search (searchable-history) "git" :mode :fuzzy))))

(describe "smartcase"
  (it "matches loosely for an all-lower-case query"
    (expect (history-search (searchable-history) "git")
            :to-have-texts '("git push" "Git log" "git commit")))

  (it "matches exactly once the query carries an upper-case character"
    (expect (history-search (searchable-history) "Git")
            :to-have-texts '("Git log")))

  (it "honours CASE-SENSITIVE only when smartcase is switched off"
    (expect (history-search (searchable-history) "git" :smartcase nil :case-sensitive t)
            :to-have-texts '("git push" "git commit"))
    (expect (history-search (searchable-history) "GIT" :smartcase nil :case-sensitive nil)
            :to-have-texts '("git push" "Git log" "git commit"))))

(describe "single-entry matching"
  (it "answers each mode for one entry"
    (let ((entry (make-history-entry "git commit -m x")))
      (expect (history-entry-match-p entry "git") :to-be t)
      (expect (history-entry-match-p entry "commit" :mode :contains) :to-be t)
      (expect (history-entry-match-p entry "git" :mode :exact) :to-be nil)
      (expect (history-entry-match-p entry "GIT" :case-sensitive t) :to-be nil)))

  (it "returns the suggestible remainder of a matching line"
    (let ((entry (make-history-entry "git commit")))
      (expect (history-entry-line-suffix entry "git ") :to-equal "commit")))

  (it "distinguishes an exhausted match from no match at all"
    (let ((entry (make-history-entry "ls")))
      ;; "" means "matched, nothing left to suggest"; NIL means "no match".
      (expect (history-entry-line-suffix entry "ls") :to-equal "")
      (expect (history-entry-line-suffix entry "cd") :to-be nil)))

  (it "reads the suffix from any line of a multi-line entry"
    (let ((entry (make-history-entry (format nil "echo one~%echo two"))))
      (expect (history-entry-line-suffix entry "echo t") :to-equal "wo"))))
