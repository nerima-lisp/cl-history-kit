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

(define-case-sensitive-predicate %text-contains-p (text query)
  "True when QUERY occurs anywhere within TEXT."
  :sensitive (search query text)
  :insensitive (search query text :test #'char-equal))

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
