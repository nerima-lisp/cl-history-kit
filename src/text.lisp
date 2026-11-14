;;;; src/text.lisp

(in-package #:history-kit)

(defun %smartcase-sensitive-p (query)
  "True when QUERY contains an upper-case character."
  (and (some #'upper-case-p query) t))

(defmacro define-case-sensitive-predicate
    (name (text query &rest extra-params) documentation
     &key bindings guard sensitive insensitive)
  "Define a text predicate from case-sensitive and insensitive forms."
  `(defun ,name (,text ,query ,@extra-params &key case-sensitive)
     ,documentation
     (let* ,bindings
       (and ,@(when guard (list guard))
            (if case-sensitive ,sensitive ,insensitive)
            t))))

(define-case-sensitive-predicate %text-prefix-p (text query)
  "True when TEXT begins with QUERY."
  :bindings ((query-length (length query)))
  :guard (<= query-length (length text))
  :sensitive (string= text query :end1 query-length)
  :insensitive (string-equal text query :end1 query-length))

(define-case-sensitive-predicate %text-equal-p (text query)
  "True when TEXT equals QUERY in its entirety."
  :sensitive (string= text query)
  :insensitive (string-equal text query))

;;; Case-insensitive matching compares characters with %CHAR-FOLD= instead of
;;; CHAR-EQUAL.  When both characters are ASCII it folds A-Z by char-code
;;; arithmetic; otherwise it defers to CHAR-EQUAL, so the result equals
;;; CHAR-EQUAL's for every pair, including Unicode letters such as KELVIN SIGN
;;; or LATIN SMALL LETTER DOTLESS I whose case relationship to ASCII letters
;;; is implementation-defined.

(declaim (inline %ascii-fold %char-fold=))

(defun %ascii-fold (code)
  "Return the lower-case char-code for the ASCII char-code CODE."
  (declare (type (integer 0 127) code))
  (if (<= (char-code #\A) code (char-code #\Z))
      (+ code (- (char-code #\a) (char-code #\A)))
      code))

(defun %char-fold= (a b)
  "True when characters A and B are equal ignoring case, as CHAR-EQUAL decides."
  (let ((code-a (char-code a))
        (code-b (char-code b)))
    (cond ((= code-a code-b) t)
          ((< (logior code-a code-b) 128)
           (= (%ascii-fold code-a) (%ascii-fold code-b)))
          (t (char-equal a b)))))

(defmacro with-specialized-strings ((&rest variables) &body body)
  "Evaluate BODY with each of VARIABLES declared as the concrete string type it
holds -- a simple character string, a simple base string, or else any string --
so the common simple cases compile to direct character access."
  (if (null variables)
      `(progn ,@body)
      (let ((variable (first variables)))
        `(typecase ,variable
           ,@(mapcar (lambda (type)
                       `(,type
                         (let ((,variable ,variable))
                           (declare (type ,type ,variable))
                           (with-specialized-strings ,(rest variables) ,@body))))
                     '((simple-array character (*)) simple-base-string))
           (t
            (let ((,variable ,variable))
              (declare (type string ,variable))
              (with-specialized-strings ,(rest variables) ,@body)))))))

(defun %search-folded (query text)
  "True when QUERY occurs in TEXT, comparing characters with %CHAR-FOLD=."
  (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
  (with-specialized-strings (query text)
    (let ((query-length (length query)))
      (loop for start of-type fixnum from 0 to (- (length text) query-length)
              thereis (loop for index of-type fixnum below query-length
                            always (%char-fold= (char text (+ start index))
                                                (char query index)))))))

(define-case-sensitive-predicate %text-contains-p (text query)
  "True when QUERY occurs anywhere within TEXT."
  :sensitive (search query text)
  :insensitive (%search-folded query text))

;;; Fuzzy matching: QUERY matches when its characters occur in TEXT in order.
;;; The score is a greedy heuristic computed in one pass over TEXT, taking the
;;; leftmost occurrence of each query character; it is not the best possible
;;; alignment.  Each matched character earns
;;;
;;;   +10  when it is the first character of TEXT,
;;;    +6  when it follows a word boundary (space, / - _ . or newline),
;;;    +8  when it directly follows the previous matched character,
;;;   -N   when N characters of TEXT were skipped since the previous match.
;;;
;;; Characters skipped before the first match cost nothing.  Because the
;;; consecutive bonus exceeds the boundary bonus, a text that starts with
;;; QUERY scores at least as high as any other text.

(defconstant +fuzzy-start-bonus+ 10)
(defconstant +fuzzy-boundary-bonus+ 6)
(defconstant +fuzzy-consecutive-bonus+ 8)

(declaim (inline %fuzzy-boundary-char-p %fuzzy-position-bonus))

(defun %fuzzy-boundary-char-p (char)
  "True when CHAR ends a word for fuzzy scoring."
  (member char '(#\Space #\/ #\- #\_ #\. #\Newline)))

(defun %fuzzy-position-bonus (text index)
  "Return the bonus for a fuzzy match at INDEX of TEXT."
  (cond ((zerop index) +fuzzy-start-bonus+)
        ((%fuzzy-boundary-char-p (char text (1- index))) +fuzzy-boundary-bonus+)
        (t 0)))

(defmacro define-fuzzy-scorer (name char-test)
  "Define NAME as a fuzzy scorer that compares characters with CHAR-TEST."
  `(defun ,name (text query)
     "Return the fuzzy score of QUERY within TEXT, or NIL when it does not match."
     (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
     (with-specialized-strings (text query)
       (let ((query-length (length query))
             (query-index 0)
             (previous -1)
             (score 0))
         (declare (type fixnum query-index previous score))
         (if (zerop query-length)
             0
             (dotimes (index (length text) nil)
               (when (,char-test (char text index) (char query query-index))
                 (incf score (%fuzzy-position-bonus text index))
                 (unless (minusp previous)
                   (if (= index (1+ previous))
                       (incf score +fuzzy-consecutive-bonus+)
                       (decf score (- index previous 1))))
                 (setf previous index)
                 (incf query-index)
                 (when (= query-index query-length)
                   (return score)))))))))

(define-fuzzy-scorer %fuzzy-score-sensitive char=)
(define-fuzzy-scorer %fuzzy-score-folded %char-fold=)

(defun %text-fuzzy-score (text query &key case-sensitive)
  "Return the fuzzy score of QUERY within TEXT, or NIL when it does not match."
  (if case-sensitive
      (%fuzzy-score-sensitive text query)
      (%fuzzy-score-folded text query)))

(define-case-sensitive-predicate %text-fuzzy-p (text query)
  "True when the characters of QUERY occur in TEXT in order."
  :sensitive (%fuzzy-score-sensitive text query)
  :insensitive (%fuzzy-score-folded text query))

(defun %map-lines (function text)
  "Call FUNCTION with each line's bounds until it returns non-NIL."
  (loop with length = (length text)
        with line-start = 0
        for newline = (position #\Newline text :start line-start)
        for line-end = (or newline length)
        thereis (funcall function line-start line-end)
        while newline
        do (setf line-start (1+ newline))))

(define-case-sensitive-predicate %line-prefix-match-p (text query line-start line-end)
  "True when the line of TEXT spanning [LINE-START, LINE-END) begins with QUERY."
  :bindings ((query-end (+ line-start (length query))))
  :guard (<= query-end line-end)
  :sensitive (string= text query :start1 line-start :end1 query-end)
  :insensitive (string-equal text query :start1 line-start :end1 query-end))

(defmacro with-each-line ((line-start line-end text) &body body)
  "Evaluate BODY with each line's bounds until it returns non-NIL."
  `(%map-lines (lambda (,line-start ,line-end) ,@body) ,text))

(defun %text-line-prefix-p (text query &key case-sensitive)
  "True when any line of TEXT begins with QUERY."
  (and (with-each-line (line-start line-end text)
         (%line-prefix-match-p text query line-start line-end
                               :case-sensitive case-sensitive))
       t))

(defun %text-line-suffix (text query &key case-sensitive)
  "Return the remainder of the first line beginning with QUERY.
Return NIL when there is no match; return the empty string for an exact match."
  (with-each-line (line-start line-end text)
    (when (%line-prefix-match-p text query line-start line-end
                                :case-sensitive case-sensitive)
      (subseq text (+ line-start (length query)) line-end))))
