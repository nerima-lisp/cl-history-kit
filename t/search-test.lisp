;;;; t/search-test.lisp
(in-package #:cl-history-kit/test)

(defun searchable-history ()
  (history-of '("git push" "Git log" "ls -la" "git commit")))

(describe "search modes"
  (it "matches a prefix by default, newest first"
    (expect (history-search (searchable-history) "git ")
            :to-have-texts (list "git push" "Git log" "git commit")))

  (it "matches whole texts under :EXACT"
    (expect (history-search (searchable-history) "ls -la" :mode :exact)
            :to-have-texts (list "ls -la")))

  (it "matches anywhere under :CONTAINS"
    (expect (history-search (searchable-history) "commit" :mode :contains)
            :to-have-texts (list "git commit")))

  (it "matches any line of a multi-line entry under :LINE-PREFIX"
    (let ((history (history-of (list (format nil "echo one~%echo two")))))
      (expect (history-search history "echo two" :mode :line-prefix)
              :to-have-texts (list (format nil "echo one~%echo two")))
      (expect (history-search history "echo two") :to-have-texts (list))))

  (it "applies smartcase and explicit sensitivity to :LINE-PREFIX"
    ;; The two entries' first lines differ only in case, so a case-sensitive
    ;; query distinguishes them by that line alone; sharing a first line would
    ;; make both match on it regardless of the second line's case.
    (let ((history (history-of (list (format nil "Echo one~%Echo two")
                                     (format nil "echo one~%echo three")))))
      (expect (history-search history "echo " :mode :line-prefix)
              :to-have-texts
              (list (format nil "Echo one~%Echo two")
                    (format nil "echo one~%echo three")))
      (expect (history-search history "Echo " :mode :line-prefix)
              :to-have-texts (list (format nil "Echo one~%Echo two")))
      (expect (history-search history "echo " :mode :line-prefix
                              :smartcase nil :case-sensitive t)
              :to-have-texts (list (format nil "echo one~%echo three")))))

  (it "returns everything for the empty query and nothing for a miss"
    (expect (length (history-search (searchable-history) "")) :to-be 4)
    (expect (history-search (searchable-history) "nope") :to-have-texts (list)))

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

(describe "limiting results"
  (it "truncates to the newest matches when the limit is smaller than the match count"
    (expect (history-search (searchable-history) "git " :limit 2)
            :to-have-texts '("git push" "Git log")))

  (it "returns everything unchanged when the limit equals the match count"
    (expect (history-search (searchable-history) "git " :limit 3)
            :to-have-texts '("git push" "Git log" "git commit")))

  (it "returns everything unchanged when the limit exceeds the match count"
    (expect (history-search (searchable-history) "git " :limit 100)
            :to-have-texts '("git push" "Git log" "git commit")))

  (it "returns everything when the limit is NIL"
    (expect (history-search (searchable-history) "git " :limit nil)
            :to-have-texts '("git push" "Git log" "git commit"))))

(describe "single-entry matching"
  (it-each ((:prefix "git" nil t)
            (:contains "commit" nil t)
            (:exact "git" nil nil)
            (:prefix "GIT" t nil))
      "MODE ~S query ~S case-sensitive ~S"
      (mode query case-sensitive expected)
    (let ((entry (make-history-entry "git commit -m x")))
      (expect (history-entry-match-p entry query :mode mode :case-sensitive case-sensitive)
              :to-be expected)))

  (it "rejects a mode outside the shared mode contract"
    (signals error
             (history-entry-match-p (make-history-entry "git commit") "git"
                                    :mode :fuzzy)))

  (it "returns the suggestible remainder of a matching line"
    (let ((entry (make-history-entry "git commit")))
      (expect (history-entry-line-suffix entry "git ") :to-equal "commit")))

  (it "distinguishes an exhausted match from no match at all"
    (let ((entry (make-history-entry "ls")))
      ;; "" means "matched, nothing left to suggest"; NIL means "no match".
      (expect (history-entry-line-suffix entry "ls") :to-equal "")
      (expect (history-entry-line-suffix entry "cd") :to-be nil)))

  (it "handles empty, trailing, and blank lines consistently"
    (dolist
        (case (list
               (list "" "" "")
               (list (format nil "ignored~%needle tail~%") "needle " "tail")
               (list (format nil "ignored~%~%needle tail") "needle " "tail")))
      (destructuring-bind (text query expected-suffix) case
        (let ((entry (make-history-entry text)))
          (expect (history-search (history-of (list text)) query
                                  :mode :line-prefix)
                  :to-have-texts (list text))
          (expect (history-entry-line-suffix entry query)
                  :to-equal expected-suffix)))))

  (it "reads the suffix from any line of a multi-line entry"
    (let ((entry (make-history-entry (format nil "echo one~%echo two"))))
      (expect (history-entry-line-suffix entry "echo t") :to-equal "wo"))))
