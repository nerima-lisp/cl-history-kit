;;;; src/search.lisp

(in-package #:history-kit)

(defun %history-matcher (mode)
  "Return the text predicate implementing MODE."
  (ecase mode
    (:prefix #'%text-prefix-p)
    (:exact #'%text-equal-p)
    (:contains #'%text-contains-p)
    (:line-prefix #'%text-line-prefix-p)
    (:fuzzy #'%text-fuzzy-p)))

(define-typed-function
  history-entry-match-p
  (entry history-entry query &key (mode :prefix) case-sensitive)
  "True when ENTRY matches QUERY under MODE.

MODE is :PREFIX (default), :EXACT, :CONTAINS, :LINE-PREFIX, or :FUZZY.
:LINE-PREFIX matches when any line of a multi-line entry begins with QUERY;
:FUZZY matches when the characters of QUERY occur in the entry in order, so
the empty QUERY matches everything."
  ((query string))
  (funcall
    (%history-matcher mode)
    (%history-entry-text entry)
    query
    :case-sensitive
    case-sensitive))

(define-typed-function
  history-entry-line-suffix
  (entry history-entry query &key case-sensitive)
  "Return the rest of the first line of ENTRY that begins with QUERY, or NIL.

This is the text an autosuggestion would append to what the user has typed so
far.  A line consisting of QUERY exactly yields the empty string, which is
distinguishable from the NIL returned when nothing matched."
  ((query string))
  (%text-line-suffix
    (%history-entry-text entry)
    query
    :case-sensitive
    case-sensitive))

(define-typed-function
  history-search
  (history history query &key (mode :prefix) case-sensitive (smartcase t) limit filter)
  "Return the entries of HISTORY matching QUERY under MODE, newest first.

MODE is :PREFIX (default), :EXACT, :CONTAINS, :LINE-PREFIX, or :FUZZY; results
stay newest first under :FUZZY too, and HISTORY-FUZZY-SEARCH ranks them by
score instead. SMARTCASE selects sensitivity from QUERY unless it is NIL.
FILTER, when non-NIL, is a predicate called with each entry that matches
QUERY; entries it rejects are left out and do not count toward LIMIT. LIMIT
bounds returned matches and stops the scan once it has been reached."
  ((query string) (limit (or null (integer 0 *))) (filter (or function symbol)))
  (let ((matcher (%history-matcher mode))
        (sensitive
         (if smartcase (%smartcase-sensitive-p query)
             case-sensitive))
        (remaining limit)
        (matches nil))
    (locally
      (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
      (block search
        (dotimes (offset (%history-count history))
          (when (eql remaining 0)
            (return-from search (nreverse matches)))
          (let ((entry (%history-entry-at history offset)))
            (when (and (funcall matcher (%history-entry-text entry) query
                                :case-sensitive sensitive)
                       (or (null filter) (funcall filter entry)))
              (push entry matches)
              (when remaining
                (decf remaining)))))
        (nreverse matches)))))

(define-typed-function
  history-entry-fuzzy-score
  (entry history-entry query &key case-sensitive)
  "Return how well QUERY fuzzily matches ENTRY as an integer, or NIL.

NIL means the characters of QUERY do not occur in the entry text in order.
Higher scores are better matches: matched characters that are adjacent, that
start the text, or that follow a word boundary (space, /, -, _, ., or newline)
raise the score, and text skipped between matched characters lowers it.  A
text that starts with QUERY scores at least as high as any other.  The score
comes from one greedy left-to-right pass, linear in the text length, so it is
a heuristic rather than the best possible alignment.  The empty QUERY scores 0."
  ((query string))
  (%text-fuzzy-score (%history-entry-text entry) query :case-sensitive case-sensitive))

(define-typed-function
  history-fuzzy-search
  (history history query &key filter limit case-sensitive (smartcase t))
  "Return the entries of HISTORY fuzzily matching QUERY, best match first.

Entries are ranked by HISTORY-ENTRY-FUZZY-SCORE, highest first; entries with
equal scores stay newest first.  SMARTCASE selects sensitivity from QUERY
unless it is NIL.  FILTER, when non-NIL, is a predicate called with each
matching entry; entries it rejects are left out.  LIMIT, when non-NIL, keeps
only that many of the best-ranked entries, so the whole history is still
scanned."
  ((query string) (filter (or function symbol)) (limit (or null (integer 0 *))))
  (let ((sensitive (if smartcase (%smartcase-sensitive-p query) case-sensitive))
        (scored nil))
    (locally
      (declare (optimize (speed 3) (safety 1) (compilation-speed 0)))
      (dotimes (offset (%history-count history))
        (let* ((entry (%history-entry-at history offset))
               (score (%text-fuzzy-score (%history-entry-text entry) query
                                         :case-sensitive sensitive)))
          (when (and score (or (null filter) (funcall filter entry)))
            (push (cons score entry) scored)))))
    (loop for (nil . entry) in (stable-sort (nreverse scored) #'> :key #'car)
          for count from 0
          while (or (null limit) (< count limit))
          collect entry)))
