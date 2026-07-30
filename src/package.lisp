;;;; src/package.lisp
;;;;
;;;; The single public package.  Everything a caller needs -- the immutable
;;;; entry value object, the bounded store, its mutating operations, search,
;;;; and the prefix-aware navigation cursor -- is exported here and nothing
;;;; else.  Internal helpers keep a leading % and stay unexported.
;;;;
;;;; Optimization stays local to internal hot paths.  A library-wide OPTIMIZE
;;;; proclamation would leak into forms compiled by a client after loading this
;;;; system; checked public boundaries retain their ordinary compiler policy.
(defpackage #:history-kit
  (:use #:cl)
  (:export
   ;; Entries
   #:history-entry
   #:make-history-entry
   #:history-entry-p
   #:history-entry-text
   #:history-entry-timestamp
   #:history-entry-exit-code
   #:history-entry-texts
   ;; Store
   #:history
   #:make-history
   #:history-p
   #:history-entries
   #:history-capacity
   #:history-count
   #:history-empty-p
   #:history-duplicate-policy
   ;; Operations
   #:history-add
   #:history-clear
   #:history-delete
   #:history-delete-if
   #:history-dedup
   #:history-merge
   ;; Search
   #:history-search
   #:history-entry-match-p
   #:history-entry-line-suffix
   ;; Navigation
   #:history-previous
   #:history-next
   #:history-navigating-p
   #:history-reset-navigation))
