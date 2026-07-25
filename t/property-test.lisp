;;;; t/property-test.lisp
;;;;
;;;; Property-based specs: instead of a handful of chosen examples, assert an
;;;; invariant over many generated inputs and let cl-weave shrink any
;;;; counterexample to a minimal failing value.
(in-package #:cl-history-kit/test)

(describe "store invariants"
  (it-property "the entry count never exceeds the capacity"
      ((texts (gen-list (gen-command-text) :max-length 12))
       (capacity (gen-integer :min 0 :max 6)))
    (let ((history (history-of texts :capacity capacity)))
      (expect (<= (history-count history) capacity) :to-be-truthy)))

  (it-property "the :REMOVE policy leaves every recorded text unique"
      ((texts (gen-list (gen-command-text) :max-length 12)))
    (let ((stored (history-entry-texts (history-entries (history-of texts)))))
      (expect (length stored) :to-be (length (remove-duplicates stored :test #'equal)))))

  (it-property "HISTORY-DEDUP leaves every remaining text unique regardless of the original duplicate policy"
      ((texts (gen-list (gen-command-text) :max-length 12))
       (policy (gen-member '(:remove :keep))))
    (let ((history (history-of texts :duplicate-policy policy)))
      (history-dedup history)
      (let ((stored (history-entry-texts (history-entries history))))
        (expect (length stored) :to-be (length (remove-duplicates stored :test #'equal))))))

  (it-property "the :KEEP policy records exactly as many entries as were added"
      ((texts (gen-list (gen-command-text) :max-length 6)))
    (let ((history (history-of texts :duplicate-policy :keep)))
      (expect (history-count history) :to-be (length texts))))

  (it-property "the newest entry is always the one most recently recorded"
      ((texts (gen-list (gen-command-text) :max-length 6))
       (newest (gen-command-text)))
    (let ((history (history-of texts)))
      (history-add history newest)
      (expect (history-entry-text (first (history-entries history)))
              :to-equal newest))))

(describe "search invariants"
  (it-property "every case-sensitive prefix result really starts with the query"
      ((texts (gen-list (gen-command-text) :max-length 10))
       (query (gen-command-text :min-length 0 :max-length 3)))
    (let ((results (history-search (history-of texts) query
                                   :smartcase nil :case-sensitive t)))
      (expect (every (lambda (entry)
                       (let ((text (history-entry-text entry)))
                         (and (<= (length query) (length text))
                              (string= query text :end2 (length query)))))
                     results)
              :to-be-truthy)))

  (it-property "the empty query matches every stored entry"
      ((texts (gen-list (gen-command-text) :max-length 10)))
    (let ((history (history-of texts)))
      (expect (length (history-search history ""))
              :to-be (history-count history)))))

(describe "navigation invariants"
  (it-property "one step back then one step forward restores the typed input"
      ((texts (gen-list (gen-command-text) :min-length 1 :max-length 8))
       (input (gen-command-text :min-length 0 :max-length 3)))
    (let ((history (history-of texts)))
      (when (history-previous history input)
        (expect (history-next history) :to-equal input)
        (expect (history-navigating-p history) :to-be-falsy))))

  (it-property "walking all the way back under any mode visits exactly the matching entries"
      ((texts (gen-list (gen-command-text) :max-length 8))
       (query (gen-command-text :min-length 0 :max-length 2))
       (mode (gen-member '(:prefix :exact :contains :line-prefix))))
    (let* ((history (history-of texts))
           (expected (history-entry-texts (history-search history query :mode mode)))
           (walked (loop for text = (history-previous history query :mode mode)
                         while text
                         collect text)))
      (expect walked :to-equal expected)))

  (it-property "a recorded entry is always the first one recalled"
      ((texts (gen-list (gen-command-text) :max-length 8))
       (newest (gen-command-text)))
    (let ((history (history-of texts)))
      (history-add history newest)
      (expect (history-previous history "") :to-equal newest)))

  (it-property "with WRAP true, walking backward past the oldest match keeps cycling instead of ever returning NIL"
      ((texts (gen-list (gen-command-text) :min-length 1 :max-length 8))
       (query (gen-command-text :min-length 0 :max-length 3))
       (extra-steps (gen-integer :min 1 :max 20)))
    (let* ((history (history-of texts))
           (match-count (length (history-search history query))))
      (when (plusp match-count)
        (expect (loop repeat (+ match-count extra-steps)
                      always (history-previous history query :wrap t))
                :to-be-truthy)
        (expect (history-navigating-p history) :to-be-truthy))))

  (it-property "with WRAP true, alternating HISTORY-PREVIOUS and HISTORY-NEXT keeps cycling in both directions instead of ever returning NIL"
      ((texts (gen-list (gen-command-text) :min-length 1 :max-length 8))
       (query (gen-command-text :min-length 0 :max-length 3))
       (steps (gen-list (gen-member '(:previous :next)) :min-length 1 :max-length 20)))
    (let* ((history (history-of texts))
           (match-count (length (history-search history query))))
      (when (plusp match-count)
        (expect (history-previous history query :wrap t) :to-be-truthy)
        (expect (loop for direction in steps
                      always (if (eq direction :previous)
                                 (history-previous history query :wrap t)
                                 (history-next history)))
                :to-be-truthy)
        (expect (history-navigating-p history) :to-be-truthy)))))

(defparameter +fuzz-alphabet+ (format nil "abcXYZ019 -_/~%")
  "A wider alphabet than +COMMAND-ALPHABET+ -- it includes newlines, so
generated texts exercise the multi-line splitting in %MAP-LINES, not only the
single-line case the small search alphabet collides into.")

(defun gen-fuzz-text (&key (min-length 0) (max-length 16))
  (gen-string :alphabet +fuzz-alphabet+ :min-length min-length :max-length max-length))

(describe "crash safety"
  (it-fuzz "search and mode-aware navigation never signal on generated text"
      ((texts (gen-list (gen-fuzz-text) :max-length 10))
       (query (gen-fuzz-text :max-length 8))
       (mode (gen-member '(:prefix :exact :contains :line-prefix)))
       (wrap (gen-member '(t nil))))
      (:trials 200)
    (let ((history (history-of texts)))
      (history-search history query :mode mode)
      (history-previous history query :mode mode :wrap wrap)
      (history-next history))))
