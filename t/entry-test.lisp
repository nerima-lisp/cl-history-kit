;;;; t/entry-test.lisp
(in-package #:cl-history-kit/test)

(describe "history entries"
  (it "records text, timestamp, and exit code"
    (let ((entry (make-history-entry "git status" :timestamp 42 :exit-code 0)))
      (expect (history-entry-text entry) :to-equal "git status")
      (expect (history-entry-timestamp entry) :to-be 42)
      (expect (history-entry-exit-code entry) :to-be 0)
      (expect (history-entry-p entry) :to-be-truthy)))

  (it "defaults the timestamp to now and the exit code to NIL"
    (let ((entry (make-history-entry "ls")))
      (expect (history-entry-exit-code entry) :to-be nil)
      (expect (integerp (history-entry-timestamp entry)) :to-be-truthy)))

  (it "copies the recorded text, so a reused input buffer cannot corrupt it"
    (let* ((buffer (make-array 2 :element-type 'character
                                 :adjustable t :fill-pointer t
                                 :initial-contents "ls"))
           (entry (make-history-entry buffer)))
      (vector-push-extend #\! buffer)
      (expect (history-entry-text entry) :to-equal "ls")))

  (it "rejects a non-string text, a non-integer timestamp, and a bad exit code"
    (signals type-error (make-history-entry 42))
    (signals type-error (make-history-entry "ls" :timestamp "now"))
    (signals type-error (make-history-entry "ls" :exit-code :ok)))

  (it "maps a list of entries to their texts"
    (expect (history-entry-texts (list (make-history-entry "b")
                                       (make-history-entry "a")))
            :to-equal '("b" "a"))))
