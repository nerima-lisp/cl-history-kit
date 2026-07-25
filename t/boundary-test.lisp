;;;; t/boundary-test.lisp
;;;;
;;;; The boundary contract itself, swept across the whole public surface
;;;; rather than spot-checked.  Every entry point is defined with
;;;; DEFINE-CHECKED-FUNCTION (src/boundary.lisp) and documented as signalling
;;;; a TYPE-ERROR for a wrong-typed argument; since 1.0.0 that is a frozen
;;;; part of the API, so it is asserted here for each one in turn instead of
;;;; being left to whichever spec file happened to think of it.
(in-package #:cl-history-kit/test)

(describe "the boundary contract"
  (it "rejects a non-history everywhere a store is required"
    (let ((entry (make-history-entry "ls")))
      ;; Readers.
      (signals type-error (history-entries :not-a-history))
      (signals type-error (history-capacity :not-a-history))
      (signals type-error (history-count :not-a-history))
      (signals type-error (history-empty-p :not-a-history))
      (signals type-error (history-duplicate-policy :not-a-history))
      ;; Operations.
      (signals type-error (history-add :not-a-history "ls"))
      (signals type-error (history-clear :not-a-history))
      (signals type-error (history-delete :not-a-history "ls"))
      (signals type-error (history-delete-if :not-a-history #'identity))
      (signals type-error (history-dedup :not-a-history))
      (signals type-error (history-merge :not-a-history (list entry)))
      ;; Search.
      (signals type-error (history-search :not-a-history "ls"))
      ;; Navigation.
      (signals type-error (history-previous :not-a-history ""))
      (signals type-error (history-next :not-a-history))
      (signals type-error (history-navigating-p :not-a-history))
      (signals type-error (history-reset-navigation :not-a-history))))

  (it "rejects a non-string everywhere text is required"
    (let ((history (history-of '("ls")))
          (entry (make-history-entry "ls")))
      (signals type-error (make-history-entry 42))
      (signals type-error (history-delete history 42))
      (signals type-error (history-search history 42))
      (signals type-error (history-entry-match-p entry 42))
      (signals type-error (history-entry-line-suffix entry 42))
      (signals type-error (history-previous history 42))))

  (it "rejects a non-entry everywhere an entry is required"
    (signals type-error (history-entry-match-p :not-an-entry "ls"))
    (signals type-error (history-entry-line-suffix :not-an-entry "ls"))
    ;; HISTORY-MERGE checks each element of a source list, not just the list.
    (signals type-error (history-merge (make-history) (list :not-an-entry))))

  (it "rejects out-of-contract constructor and search arguments"
    (signals type-error (make-history :capacity -1))
    (signals type-error (make-history :capacity :unbounded))
    (signals type-error (make-history :duplicate-policy :dedupe))
    (signals type-error (make-history-entry "ls" :timestamp "now"))
    (signals type-error (make-history-entry "ls" :exit-code :ok))
    (signals type-error (history-search (history-of '("ls")) "ls" :limit -1))
    (signals type-error (history-search (history-of '("ls")) "ls" :limit :all)))

  (it "signals before mutating, so a rejected call leaves the store untouched"
    (let ((history (history-of '("ls"))))
      (history-previous history "")
      (signals type-error (history-delete history 42))
      (expect history :to-record-texts '("ls"))
      ;; The in-progress walk survives a rejected call as well.
      (expect (history-navigating-p history) :to-be-truthy)))

  (it "accepts the boundary values its contract admits"
    ;; A zero capacity, a zero limit and an empty query are all inside the
    ;; declared types, so none of them may signal.
    (expect (history-count (make-history :capacity 0)) :to-be 0)
    (expect (history-search (history-of '("ls")) "" :limit 0) :to-equal nil)
    (expect (history-search (history-of '("ls")) "") :to-have-texts '("ls"))
    (expect (history-entry-exit-code (make-history-entry "ls" :exit-code -1))
            :to-be -1)))
