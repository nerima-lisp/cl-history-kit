;;;; t/fuzzy-test.lisp
(in-package #:cl-history-kit/test)

(defun fuzzy-score (text query &rest options)
  (apply #'history-entry-fuzzy-score (make-history-entry text) query options))

(defun reference-fuzzy-score (text query char-test)
  "Score QUERY in TEXT by the documented formula, comparing with CHAR-TEST.

Written independently of the library's scorer so a property can check both the
formula and that the ASCII fold agrees with CHAR-EQUAL."
  (if (zerop (length query))
      0
      (let ((score 0)
            (previous nil)
            (query-index 0))
        (dotimes (index (length text) nil)
          (when (funcall char-test (char text index) (char query query-index))
            (incf score (cond ((zerop index) 10)
                              ((find (char text (1- index))
                                     (list #\Space #\/ #\- #\_ #\. #\Newline))
                               6)
                              (t 0)))
            (when previous
              (if (= index (1+ previous))
                  (incf score 8)
                  (decf score (- index previous 1))))
            (setf previous index)
            (incf query-index)
            (when (= query-index (length query))
              (return score)))))))

;;; ASCII letters, Japanese, and the Unicode letters whose case relationship to
;;; ASCII is the classic trap for an ASCII case fold: KELVIN SIGN, DOTLESS I,
;;; CAPITAL I WITH DOT ABOVE, LONG S, ANGSTROM SIGN, and fullwidth A.
(defparameter +case-trap-alphabet+
  (coerce (append (coerce "aAkKiIsS -/" 'list)
                  (list (code-char #x212A) (code-char #x0131) (code-char #x0130)
                        (code-char #x017F) (code-char #x212B) (code-char #x00E5)
                        (code-char #x00C5) (code-char #xFF21) (code-char #xFF41))
                  (coerce "日本語あア" 'list))
          'string))

(defun gen-case-trap-text (&key (min-length 0) (max-length 12))
  (gen-string :alphabet +case-trap-alphabet+ :min-length min-length :max-length max-length))

(describe "fuzzy matching"
  (it-each (("git commit" "gc" t)
            ("git commit" "gtcmt" t)
            ("git commit" "git commit" t)
            ("git commit" "" t)
            ("git commit" "cg" nil)
            ("git commit" "gitx" nil)
            ("" "a" nil)
            ("ls" "lss" nil))
      "text ~S query ~S matches ~S"
      (text query expected)
    (expect (history-entry-match-p (make-history-entry text) query :mode :fuzzy)
            :to-be expected)
    (expect (and (fuzzy-score text query) t) :to-be expected))

  (it "matches Japanese queries in order"
    (expect (history-entry-match-p (make-history-entry "日本語の文章") "日語" :mode :fuzzy)
            :to-be-truthy)
    (expect (history-entry-match-p (make-history-entry "日本語の文章") "語日" :mode :fuzzy)
            :to-be-falsy)
    (expect (history-search (history-of '("日本語の文章" "英語" "日記"))
                            "日語" :mode :fuzzy)
            :to-have-texts '("日本語の文章")))

  (it "follows CASE-SENSITIVE for a single entry"
    (let ((entry (make-history-entry "Git Commit")))
      (expect (history-entry-match-p entry "gc" :mode :fuzzy) :to-be-truthy)
      (expect (history-entry-match-p entry "gc" :mode :fuzzy :case-sensitive t)
              :to-be-falsy)
      (expect (history-entry-fuzzy-score entry "gc" :case-sensitive t) :to-be nil)))

  (it "applies smartcase to fuzzy search"
    (let ((history (history-of '("Git commit" "git checkout"))))
      (expect (history-search history "gc" :mode :fuzzy)
              :to-have-texts '("Git commit" "git checkout"))
      (expect (history-search history "Gc" :mode :fuzzy) :to-have-texts '("Git commit"))
      (expect (history-fuzzy-search history "Gc") :to-have-texts '("Git commit"))
      (expect (history-fuzzy-search history "Gc" :smartcase nil)
              :to-have-texts '("Git commit" "git checkout"))))

  (it "recalls fuzzy matches with HISTORY-PREVIOUS, newest first"
    (let ((history (history-of '("git commit" "ls" "grep -c x"))))
      (expect (history-previous history "gc" :mode :fuzzy) :to-equal "git commit")
      (expect (history-previous history "gc") :to-equal "grep -c x")
      (expect (history-previous history "gc") :to-be nil)
      (expect (history-next history) :to-equal "git commit")
      (expect (history-next history) :to-equal "gc"))))

(describe "fuzzy scoring"
  (it "scores by the documented formula"
    (expect (fuzzy-score "ab" "ab") :to-be 18)
    (expect (fuzzy-score "xab" "ab") :to-be 8)
    (expect (fuzzy-score "x ab" "ab") :to-be 14)
    (expect (fuzzy-score "axxb" "ab") :to-be 8)
    (expect (fuzzy-score "anything" "") :to-be 0))

  (it "ranks contiguous matches above scattered ones"
    (expect (> (fuzzy-score "xabc" "abc") (fuzzy-score "xaxbxc" "abc")) :to-be-truthy))

  (it "ranks a match at a word boundary above one in mid-word"
    (expect (> (fuzzy-score "a commit" "com") (fuzzy-score "axcommit" "com")) :to-be-truthy)
    (expect (> (fuzzy-score "a/commit" "com") (fuzzy-score "axcommit" "com")) :to-be-truthy))

  (it "ranks a prefix match highest among texts of the same length"
    (let ((prefix (fuzzy-score "commit-x" "com")))
      (dolist (other '("a commit" "acommitx" "c-o-m-it" "x/c/o/m/"))
        (expect (> prefix (fuzzy-score other "com")) :to-be-truthy))))

  (it "rejects a non-string query and a non-entry"
    (signals type-error (history-entry-fuzzy-score (make-history-entry "ls") 'ls))
    (signals type-error (history-entry-fuzzy-score "ls" "ls"))))

(describe "ranked fuzzy search"
  (it "orders matches by score, best first"
    (let ((history (history-of '("axbxc" "abc" "xabc" "nothing"))))
      (expect (history-fuzzy-search history "abc")
              :to-have-texts '("abc" "xabc" "axbxc"))))

  (it "keeps equal scores newest first"
    (let ((history (history-of '("yab" "xab" "ab" "zab"))))
      (expect (history-fuzzy-search history "ab")
              :to-have-texts '("ab" "yab" "xab" "zab"))))

  (it "applies LIMIT after ranking"
    (let ((history (history-of '("axbxc" "xabc" "abc"))))
      (expect (history-fuzzy-search history "abc" :limit 2)
              :to-have-texts '("abc" "xabc"))
      (expect (history-fuzzy-search history "abc" :limit 0) :to-have-texts '())))

  (it "leaves out entries FILTER rejects"
    (let ((history (make-history)))
      (history-add history "abc" :exit-code 1)
      (history-add history "xabc" :exit-code 0)
      (history-add history "axbxc" :exit-code 0)
      (expect (history-fuzzy-search history "abc"
                                    :filter (lambda (entry)
                                              (eql (history-entry-exit-code entry) 0))
                                    :limit 1)
              :to-have-texts '("xabc"))))

  (it "returns nothing for an empty history or a miss, everything for the empty query"
    (expect (history-fuzzy-search (make-history) "a") :to-have-texts '())
    (expect (history-fuzzy-search (history-of '("ls")) "q") :to-have-texts '())
    (expect (history-fuzzy-search (history-of '("b" "a")) "") :to-have-texts '("b" "a")))

  (it "rejects a bad query, filter, or limit"
    (signals type-error (history-fuzzy-search (make-history) 42))
    (signals type-error (history-fuzzy-search (make-history) "a" :filter 42))
    (signals type-error (history-fuzzy-search (make-history) "a" :limit -1))))

(describe "ASCII case folding"
  (it "treats Unicode case traps exactly as CHAR-EQUAL does"
    (dolist (code '(#x212A #x0131 #x0130 #x017F #x212B #xFF21))
      (let ((char (code-char code)))
        (dolist (ascii '(#\k #\K #\i #\I #\s #\S #\a #\A))
          (let ((text (string char))
                (query (string ascii)))
            (expect (history-entry-match-p (make-history-entry text) query :mode :contains)
                    :to-be (char-equal char ascii))
            (expect (history-entry-match-p (make-history-entry text) query :mode :fuzzy)
                    :to-be (char-equal char ascii)))))))

  (it "matches the same across base, character, and non-simple strings"
    (let* ((base-text (coerce "Git Commit" 'simple-base-string))
           (character-text (coerce "Git Commit" '(simple-array character (*))))
           (buffer (make-array 2 :element-type 'character :adjustable t
                                 :fill-pointer t :initial-contents "gc")))
      (dolist (text (list base-text character-text))
        (let ((entry (make-history-entry text)))
          (expect (history-entry-fuzzy-score entry buffer) :to-be (fuzzy-score "Git Commit" "gc"))
          (expect (history-entry-fuzzy-score entry (coerce "gc" 'simple-base-string))
                  :to-be (fuzzy-score "Git Commit" "gc"))
          (expect (history-entry-match-p entry (coerce "it c" 'simple-base-string)
                                         :mode :contains)
                  :to-be-truthy)
          (expect (history-entry-match-p entry buffer :mode :contains) :to-be-falsy)))))

  (it-property "fuzzy scores agree with a CHAR-EQUAL and CHAR= reference"
      ((text (gen-case-trap-text))
       (query (gen-case-trap-text :max-length 4)))
    (expect (fuzzy-score text query)
            :to-be (reference-fuzzy-score text query #'char-equal))
    (expect (fuzzy-score text query :case-sensitive t)
            :to-be (reference-fuzzy-score text query #'char=)))

  (it-property ":CONTAINS agrees with SEARCH under CHAR-EQUAL and CHAR="
      ((text (gen-case-trap-text))
       (query (gen-case-trap-text :max-length 3)))
    (let ((entry (make-history-entry text)))
      (expect (history-entry-match-p entry query :mode :contains)
              :to-be (and (search query text :test #'char-equal) t))
      (expect (history-entry-match-p entry query :mode :contains :case-sensitive t)
              :to-be (and (search query text :test #'char=) t)))))
