;;;; t/navigation-test.lisp
(in-package #:cl-history-kit/test)

(defun walkable-history ()
  (history-of '("git push" "ls" "git commit")))

(describe "walking backward"
  (it "steps from newest to oldest"
    (let ((history (walkable-history)))
      (expect (history-previous history "") :to-equal "git push")
      (expect (history-previous history "") :to-equal "ls")
      (expect (history-previous history "") :to-equal "git commit")))

  (it "returns NIL at the oldest entry and leaves the cursor there"
    (let ((history (history-of '("ls"))))
      (expect (history-previous history "") :to-equal "ls")
      (expect (history-previous history "") :to-be nil)
      (expect (history-navigating-p history) :to-be-truthy)))

  (it "returns NIL on an empty history and starts no walk"
    (let ((history (make-history)))
      (expect (history-previous history "") :to-be nil)
      (expect (history-navigating-p history) :to-be-falsy)))

  (it "recalls a multi-line entry by any of its lines"
    (let ((history (history-of (list (format nil "echo one~%echo two")))))
      (expect (history-previous history "echo two")
              :to-equal (format nil "echo one~%echo two")))))

(describe "the frozen prefix filter"
  (it "walks only the entries matching the input typed when the walk began"
    (let ((history (walkable-history)))
      (expect (history-previous history "git") :to-equal "git push")
      (expect (history-previous history "git") :to-equal "git commit")
      (expect (history-previous history "git") :to-be nil)))

  (it "ignores the current input on later steps, keeping the original filter"
    (let ((history (walkable-history)))
      (expect (history-previous history "git") :to-equal "git push")
      ;; The buffer now shows "git push", but the filter is still "git".
      (expect (history-previous history "git push") :to-equal "git commit")))

  (it "applies smartcase to the filter"
    (let ((history (history-of '("Git log" "git push"))))
      (expect (history-previous history "Git") :to-equal "Git log")
      (expect (history-previous history "Git") :to-be nil))))

(describe "walking forward"
  (it "steps back toward the newest match"
    (let ((history (walkable-history)))
      (history-previous history "git")
      (history-previous history "git")
      (expect (history-next history) :to-equal "git push")))

  (it "restores the in-progress input when it passes the newest match"
    (let ((history (walkable-history)))
      (history-previous history "gi")
      (expect (history-next history) :to-equal "gi")
      (expect (history-navigating-p history) :to-be-falsy)))

  (it "returns NIL when no walk is in progress"
    (expect (history-next (walkable-history)) :to-be nil)))

(describe "ending a walk"
  (it "resets on request"
    (let ((history (walkable-history)))
      (history-previous history "git")
      (expect (eq (history-reset-navigation history) history) :to-be-truthy)
      (expect (history-navigating-p history) :to-be-falsy)
      ;; A fresh walk starts from the newest entry again.
      (expect (history-previous history "") :to-equal "git push")))

  (it "resets when an entry is recorded, since every index shifts"
    (let ((history (walkable-history)))
      (history-previous history "")
      (history-add history "pwd")
      (expect (history-navigating-p history) :to-be-falsy)
      (expect (history-previous history "") :to-equal "pwd")))

  (it "resets when entries are deleted or cleared"
    (let ((history (walkable-history)))
      (history-previous history "")
      (history-delete history "ls")
      (expect (history-navigating-p history) :to-be-falsy))
    (let ((history (walkable-history)))
      (history-previous history "")
      (history-clear history)
      (expect (history-navigating-p history) :to-be-falsy)))

  (it "leaves an in-progress walk alone when a delete matches nothing"
    (let ((history (walkable-history)))
      (history-previous history "")
      (expect (history-delete history "nope") :to-be 0)
      (expect (history-navigating-p history) :to-be-truthy))))
