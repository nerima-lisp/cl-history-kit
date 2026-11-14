;;;; t/access-test.lisp
(in-package #:cl-history-kit/test)

(defun map-history-texts (history &rest options)
  "Return the texts MAP-HISTORY visits in HISTORY under OPTIONS, in order."
  (let ((texts nil))
    (apply #'map-history
           (lambda (entry) (push (history-entry-text entry) texts))
           history options)
    (nreverse texts)))

(defun bytes-consed-by (function)
  "Return the bytes allocated while calling FUNCTION once."
  (let ((before (sb-ext:get-bytes-consed)))
    (funcall function)
    (- (sb-ext:get-bytes-consed) before)))

(describe "indexed access"
  (it "returns entries newest first by index and NIL past the end"
    (let ((history (history-of '("c" "b" "a"))))
      (expect (history-entry-text (history-entry-at history 0)) :to-equal "c")
      (expect (history-entry-text (history-entry-at history 2)) :to-equal "a")
      (expect (history-entry-at history 3) :to-be nil)
      (expect (history-entry-at history 1000) :to-be nil)))

  (it "follows the ring once it has wrapped past capacity"
    (let ((history (history-of '("e" "d" "c" "b" "a") :capacity 3)))
      (expect (loop for index below 4
                    for entry = (history-entry-at history index)
                    collect (and entry (history-entry-text entry)))
              :to-equal '("e" "d" "c" nil))))

  (it "returns NIL for any index of an empty history"
    (expect (history-entry-at (make-history) 0) :to-be nil)
    (expect (history-entry-at (make-history :capacity 0) 0) :to-be nil))

  (it "rejects a negative or non-integer index and a non-history"
    (signals type-error (history-entry-at (history-of '("a")) -1))
    (signals type-error (history-entry-at (history-of '("a")) 0.0))
    (signals type-error (history-entry-at :nope 0)))

  (it "returns the newest entry, or NIL when empty"
    (expect (history-entry-text (history-newest (history-of '("b" "a")))) :to-equal "b")
    (expect (history-newest (make-history)) :to-be nil)
    (signals type-error (history-newest nil))))

(describe "walking a history"
  (it "visits every entry newest first and returns NIL"
    (let ((history (history-of '("c" "b" "a"))))
      (expect (map-history-texts history) :to-equal '("c" "b" "a"))
      (expect (map-history #'identity history) :to-be nil)))

  (it "visits nothing in an empty history"
    (expect (map-history-texts (make-history)) :to-equal '()))

  (it "stops after LIMIT calls and visits nothing for a zero LIMIT"
    (let ((history (history-of '("c" "b" "a"))))
      (expect (map-history-texts history :limit 2) :to-equal '("c" "b"))
      (expect (map-history-texts history :limit 0) :to-equal '())
      (expect (map-history-texts history :limit 10) :to-equal '("c" "b" "a"))))

  (it "skips entries FILTER rejects without counting them toward LIMIT"
    (let ((history (make-history)))
      (history-add history "a" :exit-code 0)
      (history-add history "b" :exit-code 1)
      (history-add history "c" :exit-code 0)
      (history-add history "d" :exit-code 1)
      (flet ((succeeded-p (entry) (eql (history-entry-exit-code entry) 0)))
        (expect (map-history-texts history :filter #'succeeded-p) :to-equal '("c" "a"))
        (expect (map-history-texts history :filter #'succeeded-p :limit 1)
                :to-equal '("c")))))

  (it "lets FUNCTION leave early through a non-local exit"
    (let ((history (history-of '("c" "b" "a")))
          (visited nil))
      (expect (block walk
                (map-history (lambda (entry)
                               (push (history-entry-text entry) visited)
                               (when (string= (history-entry-text entry) "b")
                                 (return-from walk entry)))
                             history))
              :to-be-truthy)
      (expect visited :to-equal '("b" "c"))))

  (it "signals an error when FUNCTION or FILTER changes the history mid-walk"
    (let ((history (history-of '("c" "b" "a"))))
      (signals error
        (map-history (lambda (entry)
                       (declare (ignore entry))
                       (history-add history "z"))
                     history))
      (signals error
        (map-history #'identity history
                     :filter (lambda (entry)
                               (declare (ignore entry))
                               (history-clear history)
                               t)))))

  (it "signals an error even when the last visited entry triggers the change"
    (let ((history (history-of '("a"))))
      (signals error
        (map-history (lambda (entry)
                       (declare (ignore entry))
                       (history-add history "b"))
                     history))))

  (it "rejects a bad function, filter, limit, or history"
    (signals type-error (map-history 42 (history-of '("a"))))
    (signals type-error (map-history #'identity (history-of '("a")) :filter 42))
    (signals type-error (map-history #'identity (history-of '("a")) :limit -1))
    (signals type-error (map-history #'identity :nope))))

;;; SB-EXT:GET-BYTES-CONSED is process-wide, so a test-runner thread that
;;; allocates concurrently would be counted too.  The bound is therefore not
;;; zero but far below one allocation per call: 10,000 calls that each
;;; allocated even one cons cell would report 160,000 bytes.
(defparameter +allocation-calls+ 10000)
(defparameter +allocation-bound+ 4096)

(describe "allocation-free access"
  (it "looks up entries by index without allocating"
    (let ((history (history-of '("c" "b" "a")))
          (found 0))
      (flet ((walk ()
               (dotimes (i +allocation-calls+)
                 (when (history-entry-at history (mod i 4))
                   (incf found))
                 (when (history-newest history)
                   (incf found)))))
        (walk)
        (expect (< (bytes-consed-by #'walk) +allocation-bound+) :to-be-truthy))))

  (it "walks a history without allocating"
    (let* ((history (history-of (loop for i below 100 collect (format nil "cmd ~D" i))))
           (rounds (floor +allocation-calls+ 100))
           (visited 0)
           (counter (lambda (entry) (declare (ignore entry)) (incf visited)))
           (keep-all (lambda (entry) (declare (ignore entry)) t)))
      (flet ((walk ()
               (dotimes (i rounds)
                 (map-history counter history :filter keep-all :limit 99))))
        (walk)
        (expect (< (bytes-consed-by #'walk) +allocation-bound+) :to-be-truthy)
        (expect visited :to-be (* 2 99 rounds))))))
