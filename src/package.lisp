;;;; src/package.lisp
;;;;
;;;; The single public package.  Everything a caller needs -- the immutable
;;;; entry value object, the bounded store, its mutating operations, search,
;;;; and the prefix-aware navigation cursor -- is exported here and nothing
;;;; else.  Internal helpers keep a leading % and stay unexported.
;;;;
;;;; The global OPTIMIZE proclamation below is a deliberate choice, not the
;;;; implementation default: every public entry point already validates its
;;;; arguments at the boundary (DEFINE-CHECKED-FUNCTION, boundary.lisp), so
;;;; the bodies behind that boundary never need SAFETY 3's redundant runtime
;;;; checking to stay correct. This is loaded before every other file
;;;; (:SERIAL T in the .asd), and SBCL's OPTIMIZE proclamation is a global
;;;; compiler policy rather than a per-file one, so it governs the
;;;; compilation of the whole system from here.
(declaim (optimize (speed 3) (safety 1) (compilation-speed 0)))

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
