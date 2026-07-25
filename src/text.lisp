;;;; src/text.lisp
;;;;
;;;; Case-aware text predicates.  Every matcher in the library funnels through
;;;; these four, so "case sensitive" and "smartcase" each have exactly one
;;;; definition instead of one per call site -- search and navigation can never
;;;; drift apart on what counts as a match.
(in-package #:history-kit)

(defun %smartcase-sensitive-p (query)
  "True when QUERY should be matched case-sensitively under the smartcase rule.

A query containing an upper-case character is matched case-sensitively, an
all-lower-case one case-insensitively.  This is the familiar Vim/fish
convention: typing in lower case searches loosely, and reaching for the shift
key is taken as an explicit request for precision."
  (and (some #'upper-case-p query) t))

(defun %text-prefix-p (text query &key case-sensitive)
  "True when TEXT begins with QUERY."
  (let ((query-length (length query)))
    (and (<= query-length (length text))
         (if case-sensitive
             (string= text query :end1 query-length)
             (string-equal text query :end1 query-length))
         t)))

(defun %text-equal-p (text query &key case-sensitive)
  "True when TEXT equals QUERY in its entirety."
  (and (if case-sensitive
           (string= text query)
           (string-equal text query))
       t))

(defun %text-contains-p (text query &key case-sensitive)
  "True when QUERY occurs anywhere within TEXT."
  (and (if case-sensitive
           (search query text)
           (search query text :test #'char-equal))
       t))

(defun %map-lines (function text)
  "Call FUNCTION with the start and end index of each line of TEXT, returning
the first non-NIL result.

A recorded command can span several lines, and both line-prefix search and
prefix navigation want to match any one of them -- not only the first -- so
that recalling a multi-line command by its second line works."
  (loop with length = (length text)
        with line-start = 0
        for newline = (position #\Newline text :start line-start)
        for line-end = (or newline length)
        thereis (funcall function line-start line-end)
        while newline
        do (setf line-start (1+ newline))))

(defun %line-prefix-match-p (text query line-start line-end &key case-sensitive)
  "True when the line of TEXT spanning [LINE-START, LINE-END) begins with QUERY."
  (let ((query-end (+ line-start (length query))))
    (and (<= query-end line-end)
         (if case-sensitive
             (string= text query :start1 line-start :end1 query-end)
             (string-equal text query :start1 line-start :end1 query-end))
         t)))

(defun %text-line-prefix-p (text query &key case-sensitive)
  "True when any line of TEXT begins with QUERY."
  (and (%map-lines (lambda (line-start line-end)
                     (%line-prefix-match-p text query line-start line-end
                                           :case-sensitive case-sensitive))
                   text)
       t))

(defun %text-line-suffix (text query &key case-sensitive)
  "Return the remainder of the first line of TEXT that begins with QUERY.

Returns NIL when no line begins with QUERY, and the empty string when a line
consists of QUERY exactly -- the two are distinguishable, which is what an
autosuggestion consumer needs in order to tell \"nothing to suggest\" from
\"already complete\"."
  (%map-lines (lambda (line-start line-end)
                (when (%line-prefix-match-p text query line-start line-end
                                            :case-sensitive case-sensitive)
                  (subseq text (+ line-start (length query)) line-end)))
              text))
