;;;; t/operations-test.lisp
(in-package #:cl-history-kit/test)

(describe
  "recording entries"
  (it
    "stores the newest entry first and returns the store and the entry"
    (let ((history (make-history)))
      (multiple-value-bind (returned entry) (history-add history "ls" :exit-code 0)
        (expect (eq returned history) :to-be-truthy)
        (expect (history-entry-text entry) :to-equal "ls")
        (expect (history-entry-exit-code entry) :to-be 0))
      (history-add history "pwd")
      (expect history :to-record-texts '("pwd" "ls"))))
  (it
    "moves a repeated command to the top under the default :REMOVE policy"
    (expect
      (history-of '("a" "c" "b" "a"))
      :to-record-texts
      '("a" "c" "b")))
  (it
    "compacts a full wrapped ring when a default-policy command repeats"
    (let ((history (history-of '("d" "c" "b" "a") :capacity 4)))
      (history-add history "b")
      (expect history :to-record-texts '("b" "d" "c" "a"))
      (history-add history "a")
      (expect history :to-record-texts '("a" "b" "d" "c"))
      (history-add history "d")
      (expect history :to-record-texts '("d" "a" "b" "c"))))
  (it
    "keeps every repeat under the :KEEP policy"
    (expect
      (history-of '("a" "c" "b" "a") :duplicate-policy :keep)
      :to-record-texts
      '("a" "c" "b" "a")))
  (it
    "accepts an explicit timestamp so a persisted entry is not restamped"
    (let ((history (make-history)))
      (history-add history "ls" :timestamp 7)
      (expect (history-entry-timestamp (first (history-entries history))) :to-be 7))))

(describe
  "clearing and deleting"
  (it
    "clears every entry"
    (let ((history (history-of '("b" "a"))))
      (expect (eq (history-clear history) history) :to-be-truthy)
      (expect (history-empty-p history) :to-be-truthy)))
  (it
    "deletes exact matches and reports how many went"
    (let ((history (history-of '("c" "b" "a") :duplicate-policy :keep)))
      (expect (history-delete history "b") :to-be 1)
      (expect history :to-record-texts '("c" "a"))))
  (it
    "is case-sensitive by default and case-insensitive on request"
    (expect (history-delete (history-of '("LS")) "ls") :to-be 0)
    (expect (history-delete (history-of '("LS")) "ls" :case-sensitive nil) :to-be 1))
  (it
    "deletes every copy when duplicates were kept"
    (let ((history (history-of '("a" "b" "a") :duplicate-policy :keep)))
      (expect (history-delete history "a") :to-be 2)
      (expect history :to-record-texts '("b")))))

(describe
  "deduplicating"
  (it
    "removes later repeats and reports how many went, keeping the newest of each text"
    (let ((history (history-of '("a" "c" "b" "a") :duplicate-policy :keep)))
      (expect (history-dedup history) :to-be 1)
      (expect history :to-record-texts '("a" "c" "b"))))
  (it
    "resets navigation only when it actually removes something"
    (let ((history (history-of '("a" "c" "b" "a") :duplicate-policy :keep)))
      (history-previous history "")
      (expect (history-dedup history) :to-be 1)
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "leaves an in-progress walk alone when there is nothing to dedup"
    (let ((history (history-of '("c" "b" "a") :duplicate-policy :keep)))
      (history-previous history "")
      (expect (history-dedup history) :to-be 0)
      (expect (history-navigating-p history) :to-be-truthy))))

(
  describe
  "deleting by predicate"
  (it
    "deletes every entry with a non-zero exit code and reports how many went"
    (let ((history (make-history)))
      (history-add history "ls" :exit-code 0)
      (history-add history "false-cmd" :exit-code 1)
      (history-add history "typo" :exit-code 127)
      (expect
        (history-delete-if
          history
          (lambda (entry) (/= (history-entry-exit-code entry) 0)))
        :to-be 2)
      (expect history :to-record-texts '("ls"))))
  (it
    "deletes every entry older than a given timestamp"
    (let ((history (make-history)))
      (history-add history "old" :timestamp 100)
      (history-add history "newer" :timestamp 200)
      (history-add history "newest" :timestamp 300)
      (expect
        (history-delete-if
          history
          (lambda (entry) (< (history-entry-timestamp entry) 200)))
        :to-be 1)
      (expect history :to-record-texts '("newest" "newer"))))
  (it
    "resets navigation only when it actually deletes something"
    (let ((history (make-history)))
      (history-add history "ls" :exit-code 0)
      (history-add history "bad" :exit-code 1)
      (history-previous history "")
      (expect
        (history-delete-if
          history
          (lambda (entry) (/= (history-entry-exit-code entry) 0)))
        :to-be 1)
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "leaves an in-progress walk alone when the predicate matches nothing"
    (let ((history (history-of '("ls" "pwd"))))
      (history-previous history "")
      (expect
        (history-delete-if history (lambda (entry) (declare (ignore entry)) nil))
        :to-be 0)
      (expect (history-navigating-p history) :to-be-truthy)))
  (it
    "leaves HISTORY-DELETE matching exact text only, unaffected by predicate-based deletion"
    (let ((history (history-of '("git commit" "git"))))
      (expect (history-delete history "git commit -m x") :to-be 0)
      (expect (history-delete history "git commit") :to-be 1)
      (expect history :to-record-texts '("git"))))
  (it
    "rejects a predicate mutation while preserving the mutation and a coherent navigation state"
    (let ((history (history-of (list "ls"))))
      (expect (history-previous history "") :to-equal "ls")
      (signals
        error
        (history-delete-if
          history
          (lambda (entry)
            (declare (ignore entry))
            (history-add history "pwd")
            nil)))
      (expect history :to-record-texts (list "pwd" "ls"))
      (expect (history-navigating-p history) :to-be-falsy)
      (expect (history-previous history "") :to-equal "pwd"))))

(describe
  "bounded recording"
  (it
    "drops the former oldest entry without mutating a published snapshot"
    (let ((history (history-of (list "b" "a") :capacity 2 :duplicate-policy :keep))
          (snapshot nil))
      (setf snapshot (history-entries history))
      (history-add history "c")
      (expect history :to-record-texts (list "c" "b"))
      (expect (history-count history) :to-be 2)
      (expect (history-entry-texts snapshot) :to-equal (list "b" "a"))))
  (it
    "remains correct after repeated default-policy evictions and re-recording"
    (let ((history (make-history :capacity 2)))
      (dolist (text (list "a" "b" "c" "a" "d" "b"))
        (history-add history text))
      (expect history :to-record-texts (list "b" "d")))))

(describe
  "recording entry metadata"
  (it
    "stores cwd, duration, origin, and session on the recorded entry"
    (let ((history (make-history)))
      (multiple-value-bind (returned entry)
          (history-add history "make" :cwd "/src" :duration-ms 900
                                      :origin :agent :session "s-1")
        (expect (eq returned history) :to-be-truthy)
        (expect (eq entry (first (history-entries history))) :to-be-truthy)
        (expect (history-entry-cwd entry) :to-equal "/src")
        (expect (history-entry-duration-ms entry) :to-be 900)
        (expect (history-entry-origin entry) :to-be :agent)
        (expect (history-entry-session entry) :to-equal "s-1"))))
  (it
    "rejects badly typed metadata without recording anything"
    (let ((history (make-history)))
      (signals type-error (history-add history "ls" :duration-ms -1))
      (signals type-error (history-add history "ls" :origin "typed"))
      (expect (history-empty-p history) :to-be-truthy)))
  (it
    "replaces the older entry and its metadata when :REMOVE re-records a text"
    (let ((history (make-history)))
      (history-add history "make" :timestamp 1 :exit-code 2 :cwd "/old"
                                  :duration-ms 10 :origin :typed :session "s-1")
      (history-add history "ls")
      (history-add history "make" :timestamp 3)
      (expect history :to-record-texts '("make" "ls"))
      (let ((entry (first (history-entries history))))
        (expect (history-entry-timestamp entry) :to-be 3)
        (expect (history-entry-exit-code entry) :to-be nil)
        (expect (history-entry-cwd entry) :to-be nil)
        (expect (history-entry-duration-ms entry) :to-be nil)
        (expect (history-entry-origin entry) :to-be nil)
        (expect (history-entry-session entry) :to-be nil))))
  (it
    "keeps metadata on the entries HISTORY-DEDUP and HISTORY-DELETE-IF leave behind"
    (let ((history (make-history :duplicate-policy :keep)))
      (history-add history "ls" :cwd "/old")
      (history-add history "bad" :exit-code 1)
      (history-add history "ls" :cwd "/new" :duration-ms 5 :origin :ai :session "s-2")
      (expect (history-dedup history) :to-be 1)
      (expect (history-delete-if history
                                 (lambda (entry) (eql (history-entry-exit-code entry) 1)))
              :to-be 1)
      (expect history :to-record-texts '("ls"))
      (let ((entry (first (history-entries history))))
        (expect (history-entry-cwd entry) :to-equal "/new")
        (expect (history-entry-duration-ms entry) :to-be 5)
        (expect (history-entry-origin entry) :to-be :ai)
        (expect (history-entry-session entry) :to-equal "s-2")))))
