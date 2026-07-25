;;;; t/store-test.lisp
(in-package #:cl-history-kit/test)

(describe "the store"
  (it "starts empty with the documented defaults"
    (let ((history (make-history)))
      (expect (history-p history) :to-be-truthy)
      (expect (history-empty-p history) :to-be-truthy)
      (expect (history-count history) :to-be 0)
      (expect (history-capacity history) :to-be 10000)
      (expect (history-duplicate-policy history) :to-be :remove)))

  (it "drops the oldest entries once capacity is reached"
    (let ((history (history-of '("d" "c" "b" "a") :capacity 2)))
      (expect history :to-record-texts '("d" "c"))
      (expect (history-count history) :to-be 2)))

  (it "accepts a zero capacity and then records nothing"
    (let ((history (history-of '("a") :capacity 0)))
      (expect (history-empty-p history) :to-be-truthy)))

  (it "hands back a fresh entry list, so a caller cannot mutate the store"
    (let* ((history (history-of '("b" "a")))
           (entries (history-entries history)))
      (setf (first entries) :clobbered)
      (expect history :to-record-texts '("b" "a"))))

  (it "rejects a bad capacity or duplicate policy"
    (signals type-error (make-history :capacity -1))
    (signals type-error (make-history :capacity :unbounded))
    (signals type-error (make-history :duplicate-policy :dedupe)))

  (it "rejects a non-history where a history is required"
    (signals type-error (history-count :not-a-history))
    (signals type-error (history-entries nil))))
