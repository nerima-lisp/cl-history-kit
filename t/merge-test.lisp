;;;; t/merge-test.lisp
(in-package #:cl-history-kit/test)

(it
  "preserves entry timestamps and exit codes"
  (let* ((target (make-history))
         (timestamp 3984928651)
         (entry (make-history-entry "build" :timestamp timestamp :exit-code 17)))
    (history-merge target (list entry))
    (let ((merged (first (history-entries target))))
      (expect (history-entry-timestamp merged) :to-equal timestamp)
      (expect (history-entry-exit-code merged) :to-equal 17))))

(describe "merging"
  (it "merges another history, newest-first order preserved"
    (let ((target (history-of '("b" "a")))
          (source (history-of '("d" "c"))))
      (history-merge target source)
      (expect target :to-record-texts '("d" "c" "b" "a"))))

  (it "merges a bare list of entries"
    (let ((target (history-of '("a"))))
      (history-merge target (list (make-history-entry "c") (make-history-entry "b")))
      (expect target :to-record-texts '("c" "b" "a"))))

  (it "preserves the timestamp and exit code of each merged entry"
    (let ((target (make-history)))
      (history-merge target (list (make-history-entry "ls" :timestamp 11 :exit-code 3)))
      (let ((entry (first (history-entries target))))
        (expect (history-entry-timestamp entry) :to-be 11)
        (expect (history-entry-exit-code entry) :to-be 3))))

  (it "applies the target's :REMOVE duplicate policy to merged entries"
    (let ((target (history-of '("a"))))
      (history-merge target (history-of '("a")))
      (expect target :to-record-texts '("a"))))

  (it "bounds a :REMOVE merge at capacity, dropping the target's own entries entirely once source entries fill it"
    (let ((target (history-of '("b" "a") :capacity 2))
          (source (history-of '("d" "c" "e"))))
      (history-merge target source)
      (expect target :to-record-texts '("d" "c"))))

  (it "leaves a zero-capacity history empty after merging"
    (let ((target (make-history :capacity 0)))
      (history-merge target (history-of '("a")))
      (expect (history-empty-p target) :to-be-truthy)))

  (it "keeps duplicate texts when the target's duplicate policy is :KEEP"
    (let ((target (history-of '("a") :duplicate-policy :keep)))
      (history-merge target (history-of '("a")))
      (expect target :to-record-texts '("a" "a"))))

  (it "merges into a full :KEEP history in source-first order and resets navigation"
    (let ((target (history-of '("c" "b" "a")
                              :capacity 3
                              :duplicate-policy :keep)))
      (expect (history-previous target "") :to-equal "c")
      (history-merge target
                     (list (make-history-entry "e")
                           (make-history-entry "d")))
      (expect target :to-record-texts '("e" "d" "c"))
      (expect (history-count target) :to-be 3)
      (expect (history-navigating-p target) :to-be-falsy)))

  (it "makes a full :KEEP merge visible to predicate reentrancy checks"
    ;; REMOVE-IF calls its predicate once per scanned entry regardless of the
    ;; answer, so a 3-entry snapshot calls this predicate 3 times; MERGED
    ;; guards the reentrant merge to fire exactly once, matching this test's
    ;; single-mutation intent.
    (let ((target (history-of '("c" "b" "a")
                              :capacity 3
                              :duplicate-policy :keep))
          (merged nil))
      (signals error
        (history-delete-if
         target
         (lambda (entry)
           (declare (ignore entry))
           (unless merged
             (setf merged t)
             (history-merge target (list (make-history-entry "d"))))
           nil)))
      (expect target :to-record-texts '("d" "c" "b"))))

  (it "rejects a source that is neither a history nor a list"
    (signals type-error (history-merge (make-history) :nope))))
