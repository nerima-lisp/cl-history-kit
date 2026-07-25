;;;; t/operations-test.lisp
(in-package #:cl-history-kit/test)

(describe "recording entries"
  (it "stores the newest entry first and returns the store and the entry"
    (let ((history (make-history)))
      (multiple-value-bind (returned entry) (history-add history "ls" :exit-code 0)
        (expect (eq returned history) :to-be-truthy)
        (expect (history-entry-text entry) :to-equal "ls")
        (expect (history-entry-exit-code entry) :to-be 0))
      (history-add history "pwd")
      (expect history :to-record-texts '("pwd" "ls"))))

  (it "moves a repeated command to the top under the default :REMOVE policy"
    (expect (history-of '("a" "c" "b" "a")) :to-record-texts '("a" "c" "b")))

  (it "keeps every repeat under the :KEEP policy"
    (expect (history-of '("a" "c" "b" "a") :duplicate-policy :keep)
            :to-record-texts '("a" "c" "b" "a")))

  (it "accepts an explicit timestamp so a persisted entry is not restamped"
    (let ((history (make-history)))
      (history-add history "ls" :timestamp 7)
      (expect (history-entry-timestamp (first (history-entries history))) :to-be 7))))

(describe "clearing and deleting"
  (it "clears every entry"
    (let ((history (history-of '("b" "a"))))
      (expect (eq (history-clear history) history) :to-be-truthy)
      (expect (history-empty-p history) :to-be-truthy)))

  (it "deletes exact matches and reports how many went"
    (let ((history (history-of '("c" "b" "a") :duplicate-policy :keep)))
      (expect (history-delete history "b") :to-be 1)
      (expect history :to-record-texts '("c" "a"))))

  (it "is case-sensitive by default and case-insensitive on request"
    (expect (history-delete (history-of '("LS")) "ls") :to-be 0)
    (expect (history-delete (history-of '("LS")) "ls" :case-sensitive nil) :to-be 1))

  (it "deletes every copy when duplicates were kept"
    (let ((history (history-of '("a" "b" "a") :duplicate-policy :keep)))
      (expect (history-delete history "a") :to-be 2)
      (expect history :to-record-texts '("b")))))

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

  (it "applies the target's duplicate policy to merged entries"
    (let ((target (history-of '("a"))))
      (history-merge target (history-of '("a")))
      (expect target :to-record-texts '("a"))))

  (it "rejects a source that is neither a history nor a list"
    (signals type-error (history-merge (make-history) :nope))))
