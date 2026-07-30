;;;; t/navigation-test.lisp
(in-package #:cl-history-kit/test)

(defun walkable-history ()
  (history-of '("git push" "ls" "git commit")))

(describe
  "walking backward"
  (it
    "steps from newest to oldest"
    (let ((history (walkable-history)))
      (expect (history-previous history "") :to-equal "git push")
      (expect (history-previous history "") :to-equal "ls")
      (expect (history-previous history "") :to-equal "git commit")))
  (it
    "returns NIL at the oldest entry and leaves the cursor there"
    (let ((history (history-of '("ls"))))
      (expect (history-previous history "") :to-equal "ls")
      (expect (history-previous history "") :to-be nil)
      (expect (history-navigating-p history) :to-be-truthy)))
  (it
    "returns NIL on an empty history and starts no walk"
    (let ((history (make-history)))
      (expect (history-previous history "") :to-be nil)
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "returns NIL on an initial mismatch and starts no walk"
    (let ((history (walkable-history)))
      (expect (history-previous history "missing") :to-be nil)
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "recalls a multi-line entry by any of its lines"
    (let ((history (history-of (list (format nil "echo one~%echo two")))))
      (expect
        (history-previous history "echo two")
        :to-equal
        (format nil "echo one~%echo two")))))

(describe
  "the frozen prefix filter"
  (it
    "walks only the entries matching the input typed when the walk began"
    (let ((history (walkable-history)))
      (expect (history-previous history "git") :to-equal "git push")
      (expect (history-previous history "git") :to-equal "git commit")
      (expect (history-previous history "git") :to-be nil)))
  (it
    "ignores the current input on later steps, keeping the original filter"
    (let ((history (walkable-history)))
      (expect (history-previous history "git") :to-equal "git push")
      (expect (history-previous history "git push") :to-equal "git commit")))
  (it
    "copies a mutable origin before starting the walk"
    (let* ((history (walkable-history))
           (origin (copy-seq "gi")))
      (expect (history-previous history origin) :to-equal "git push")
      (setf (char origin 0) #\X)
      (expect (history-next history) :to-equal "gi")))
  (it
    "applies smartcase to the filter"
    (let ((history (history-of '("Git log" "git push"))))
      (expect (history-previous history "Git") :to-equal "Git log")
      (expect (history-previous history "Git") :to-be nil))))

(describe
  "walking forward"
  (it
    "steps back toward the newest match"
    (let ((history (walkable-history)))
      (history-previous history "git")
      (history-previous history "git")
      (expect (history-next history) :to-equal "git push")))
  (it
    "restores the in-progress input when it passes the newest match"
    (let ((history (walkable-history)))
      (history-previous history "gi")
      (expect (history-next history) :to-equal "gi")
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "returns NIL when no walk is in progress"
    (expect (history-next (walkable-history)) :to-be nil)))

(describe "an explicit match mode"
  (it-each ((:prefix "l" ("ls"))
            (:exact "ls" ("ls"))
            (:contains "s" ("git push" "ls")))
      "walks ~A-mode matches for the query ~S"
      (mode query expected)
    (let ((history (walkable-history)))
      (expect (loop for text = (history-previous history query :mode mode)
                    while text
                    collect text)
              :to-equal expected)))

  (it "recalls a multi-line entry under :LINE-PREFIX by any of its lines"
    (let ((history (history-of (list (format nil "echo one~%echo two")))))
      (expect (history-previous history "echo two" :mode :line-prefix)
              :to-equal (format nil "echo one~%echo two"))))

  (it "freezes the mode from the first call, like the prefix and the origin"
    (let ((history (walkable-history)))
      (expect (history-previous history "s" :mode :contains) :to-equal "git push")
      ;; A later call's :MODE is ignored, same as its CURRENT-INPUT.
      (expect (history-previous history "ls" :mode :exact) :to-equal "ls")))

  (it "rejects an unknown mode, same as HISTORY-SEARCH"
    (signals error (history-previous (walkable-history) "git" :mode :fuzzy))))

(describe "wraparound"
  (it "wraps to the newest match instead of returning NIL when stepping past the oldest"
    (let ((history (walkable-history)))
      (history-previous history "" :wrap t)
      (history-previous history "" :wrap t)
      (history-previous history "" :wrap t)
      (expect (history-previous history "" :wrap t) :to-equal "git push")))

  (it "wraps to the oldest match instead of restoring the origin when stepping past the newest"
    (let ((history (history-of '("ls" "git push" "git commit"))))
      (expect (history-previous history "git" :wrap t) :to-equal "git push")
      (expect (history-next history) :to-equal "git commit")
      (expect (history-navigating-p history) :to-be-truthy)))

  (it "leaves the default :WRAP NIL unchanged, stopping instead of wrapping at either end"
    (let ((history (history-of '("ls"))))
      (expect (history-previous history "") :to-equal "ls")
      (expect (history-previous history "") :to-be nil))
    (let ((history (walkable-history)))
      (history-previous history "gi")
      (expect (history-next history) :to-equal "gi")
      (expect (history-navigating-p history) :to-be-falsy)))

  (it "freezes wrap from the first call, like the mode and the prefix"
    (let ((history (history-of '("ls"))))
      (expect (history-previous history "" :wrap nil) :to-equal "ls")
      ;; A later call's :WRAP is ignored, same as its :MODE.
      (expect (history-previous history "" :wrap t) :to-be nil)))

  (it "cycles back to the same match when HISTORY-NEXT wraps from a single match sitting at cursor 0"
    (let ((history (history-of '("ls"))))
      (expect (history-previous history "" :wrap t) :to-equal "ls")
      ;; Cursor 0 is the newest match, not "not navigating" -- HISTORY-NEXT
      ;; must still wrap here instead of falling through to origin-restore.
      (expect (history-next history) :to-equal "ls")
      (expect (history-navigating-p history) :to-be-truthy)))

  (it "wraps from the newest match at cursor 0 to the oldest of two matches"
    (let ((history (history-of '("git commit" "git push"))))
      (expect (history-previous history "git" :wrap t) :to-equal "git commit")
      (expect (history-next history) :to-equal "git push")
      (expect (history-navigating-p history) :to-be-truthy))))

(describe
  "explicit case sensitivity while walking"
  (it-each ((t nil "git" ("git push" "Git log" "git commit"))
            (t nil "Git" ("Git log"))
            (nil t "git" ("git push" "git commit"))
            (nil nil "GIT" ("git push" "Git log" "git commit")))
      "smartcase ~S case-sensitive ~S query ~S"
      (smartcase case-sensitive query expected)
    (let ((history (searchable-history)))
      (expect
        (loop for text = (history-previous history query :mode :prefix
                                            :smartcase smartcase :case-sensitive case-sensitive)
              while text
              collect text)
        :to-equal
        expected))))

;;; WRAP, SMARTCASE and CASE-SENSITIVE are frozen into cursor slots typed
;;; BOOLEAN -- the strict (MEMBER T NIL) -- but they are documented as
;;; generalized booleans, as every other flag in the library is.  Nothing but
;;; a walk that actually starts ever writes those slots, so these specs step
;;; far enough to reach the write.
(describe
  "ending a walk"
  (it
    "resets on request"
    (let ((history (walkable-history)))
      (history-previous history "git")
      (expect (eq (history-reset-navigation history) history) :to-be-truthy)
      (expect (history-navigating-p history) :to-be-falsy)
      (expect (history-previous history "") :to-equal "git push")))
  (it
    "resets when an entry is recorded, since every index shifts"
    (let ((history (walkable-history)))
      (history-previous history "")
      (history-add history "pwd")
      (expect (history-navigating-p history) :to-be-falsy)
      (expect (history-previous history "") :to-equal "pwd")))
  (it
    "resets an active walk when a nonempty merge moves entries"
    (let ((history (walkable-history)))
      (expect (history-previous history "") :to-equal "git push")
      (expect (eq (history-merge history (list (make-history-entry "pwd"))) history)
              :to-be-truthy)
      (expect (history-navigating-p history) :to-be-falsy)
      (expect (history-previous history "") :to-equal "pwd")))
  (it
    "preserves an active walk when an empty merge cannot move any entry"
    (let ((history (walkable-history)))
      (expect (history-previous history "git") :to-equal "git push")
      (expect (eq (history-merge history nil) history) :to-be-truthy)
      (expect (history-navigating-p history) :to-be-truthy)
      (expect (history-previous history "ignored") :to-equal "git commit")))
  (it
    "resets when entries are deleted or cleared"
    (let ((history (walkable-history)))
      (history-previous history "")
      (history-delete history "git push")
      (expect (history-navigating-p history) :to-be-falsy)
      (history-previous history "")
      (history-clear history)
      (expect (history-navigating-p history) :to-be-falsy)))
  (it
    "leaves an in-progress walk alone when a delete matches nothing"
    (let ((history (walkable-history)))
      (history-previous history "")
      (expect (history-delete history "nope") :to-be 0)
      (expect (history-navigating-p history) :to-be-truthy))))

(describe
  "navigation cache invalidation"
  (it
    "rebuilds candidates after a history mutation"
    (let ((history (history-of (list "git push" "git commit"))))
      (expect (history-previous history "git") :to-equal "git push")
      (history-add history "git status")
      (expect (history-previous history "git") :to-equal "git status"))))

(describe
  "navigation result immutability"
  (it
    "does not expose the stored entry text through the cursor cache"
    (let* ((history (history-of '("ls")))
           (text (history-previous history "")))
      (setf (char text 0) #\X)
      (history-reset-navigation history)
      (expect (history-previous history "") :to-equal "ls"))))
