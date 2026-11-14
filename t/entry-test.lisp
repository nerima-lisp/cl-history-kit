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

(describe "history entry immutability"
  (it "returns a copy, so a caller cannot mutate stored text"
    (let* ((entry (make-history-entry "ls"))
           (text (history-entry-text entry)))
      (setf (char text 0) #\X)
      (expect (history-entry-text entry) :to-equal "ls"))))

(describe "history entry metadata"
  (it "defaults cwd, duration, origin, and session to NIL"
    (let ((entry (make-history-entry "ls")))
      (expect (history-entry-cwd entry) :to-be nil)
      (expect (history-entry-duration-ms entry) :to-be nil)
      (expect (history-entry-origin entry) :to-be nil)
      (expect (history-entry-session entry) :to-be nil)))

  (it "records cwd, duration, origin, and session"
    (let ((entry (make-history-entry "make" :cwd "/src" :duration-ms 1500
                                            :origin :typed :session "s-1")))
      (expect (history-entry-cwd entry) :to-equal "/src")
      (expect (history-entry-duration-ms entry) :to-be 1500)
      (expect (history-entry-origin entry) :to-be :typed)
      (expect (history-entry-session entry) :to-equal "s-1")))

  (it "rejects a bad cwd, duration, origin, or session"
    (signals type-error (make-history-entry "ls" :cwd :here))
    (signals type-error (make-history-entry "ls" :duration-ms -1))
    (signals type-error (make-history-entry "ls" :duration-ms 1.5))
    (signals type-error (make-history-entry "ls" :origin "typed"))
    (signals type-error (make-history-entry "ls" :session 7)))

  (it "copies cwd and session on the way in and on the way out"
    (let* ((cwd (copy-seq "/src"))
           (session (copy-seq "s-1"))
           (entry (make-history-entry "ls" :cwd cwd :session session)))
      (setf (char cwd 0) #\X
            (char session 0) #\X)
      (expect (history-entry-cwd entry) :to-equal "/src")
      (expect (history-entry-session entry) :to-equal "s-1")
      (setf (char (history-entry-cwd entry) 0) #\X
            (char (history-entry-session entry) 0) #\X)
      (expect (history-entry-cwd entry) :to-equal "/src")
      (expect (history-entry-session entry) :to-equal "s-1")))

  (it-each ((:typed) (:proposal) (:agent) (:ai) (:origin-from-a-future-host))
      "keeps origin ~S as given, known or not"
      (origin)
    (expect (history-entry-origin (make-history-entry "ls" :origin origin))
            :to-be origin)
    (expect (history-entry-origin
             (history-entry-from-plist
              (history-entry-plist (make-history-entry "ls" :origin origin))))
            :to-be origin)))

(describe "history entry plists"
  (it "writes the text and timestamp and omits NIL metadata"
    (expect (history-entry-plist (make-history-entry "ls" :timestamp 42))
            :to-equal '(:text "ls" :timestamp 42)))

  (it "writes every non-NIL field"
    (expect (history-entry-plist
             (make-history-entry "make" :timestamp 42 :exit-code 0 :cwd "/src"
                                        :duration-ms 1500 :origin :ai :session "s-1"))
            :to-equal '(:text "make" :timestamp 42 :exit-code 0 :cwd "/src"
                        :duration-ms 1500 :origin :ai :session "s-1")))

  (it "hands out fresh strings, so editing the plist cannot touch the entry"
    (let* ((entry (make-history-entry "ls" :cwd "/src" :session "s-1"))
           (plist (history-entry-plist entry)))
      (setf (char (getf plist :text) 0) #\X
            (char (getf plist :cwd) 0) #\X
            (char (getf plist :session) 0) #\X)
      (expect (history-entry-text entry) :to-equal "ls")
      (expect (history-entry-cwd entry) :to-equal "/src")
      (expect (history-entry-session entry) :to-equal "s-1")))

  (it "round-trips every field"
    (let* ((plist '(:text "make" :timestamp 42 :exit-code 2 :cwd "/src"
                    :duration-ms 0 :origin :proposal :session "s-1"))
           (entry (history-entry-from-plist plist)))
      (expect (history-entry-text entry) :to-equal "make")
      (expect (history-entry-timestamp entry) :to-be 42)
      (expect (history-entry-exit-code entry) :to-be 2)
      (expect (history-entry-cwd entry) :to-equal "/src")
      (expect (history-entry-duration-ms entry) :to-be 0)
      (expect (history-entry-origin entry) :to-be :proposal)
      (expect (history-entry-session entry) :to-equal "s-1")
      (expect (history-entry-plist entry) :to-equal plist)))

  (it "reads an old record carrying only text, timestamp, and exit code"
    (let ((entry (history-entry-from-plist '(:text "ls" :timestamp 42 :exit-code 1))))
      (expect (history-entry-timestamp entry) :to-be 42)
      (expect (history-entry-exit-code entry) :to-be 1)
      (expect (history-entry-cwd entry) :to-be nil)
      (expect (history-entry-duration-ms entry) :to-be nil)
      (expect (history-entry-origin entry) :to-be nil)
      (expect (history-entry-session entry) :to-be nil)))

  (it "reads a record with only text as timestamp 0 instead of restamping it"
    (let ((entry (history-entry-from-plist '(:text "ls"))))
      (expect (history-entry-text entry) :to-equal "ls")
      (expect (history-entry-timestamp entry) :to-be 0)
      (expect (history-entry-exit-code entry) :to-be nil)
      (expect (history-entry-origin entry) :to-be nil)))

  (it "ignores unknown keys and keeps an unknown origin"
    (let ((entry (history-entry-from-plist
                  '(:text "ls" :timestamp 42 :mood :cheerful :origin :hologram))))
      (expect (history-entry-text entry) :to-equal "ls")
      (expect (history-entry-origin entry) :to-be :hologram)
      (expect (history-entry-plist entry)
              :to-equal '(:text "ls" :timestamp 42 :origin :hologram))))

  (it "rejects a missing or non-string text and wrongly typed fields"
    (signals type-error (history-entry-from-plist '(:timestamp 42)))
    (signals type-error (history-entry-from-plist '(:text 42)))
    (signals type-error (history-entry-from-plist '(:text "ls" :timestamp "now")))
    (signals type-error (history-entry-from-plist '(:text "ls" :exit-code :ok)))
    (signals type-error (history-entry-from-plist '(:text "ls" :cwd 1)))
    (signals type-error (history-entry-from-plist '(:text "ls" :duration-ms -5)))
    (signals type-error (history-entry-from-plist '(:text "ls" :origin "ai")))
    (signals type-error (history-entry-from-plist '(:text "ls" :session :s))))

  (it "rejects input that is not an even-length proper list"
    (signals error (history-entry-from-plist "ls"))
    (signals error (history-entry-from-plist '(:text "ls" :timestamp)))
    (signals error (history-entry-from-plist '(:text "ls" . :dotted)))
    (let ((circular (list :text "ls")))
      (setf (cdr (last circular)) circular)
      (signals error (history-entry-from-plist circular)))))
