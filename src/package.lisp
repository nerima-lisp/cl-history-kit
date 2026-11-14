;;;; src/package.lisp

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
   #:history-entry-cwd
   #:history-entry-duration-ms
   #:history-entry-origin
   #:history-entry-session
   #:history-entry-texts
   #:history-entry-plist
   #:history-entry-from-plist
   ;; Store
   #:history
   #:make-history
   #:history-p
   #:history-entries
   #:history-capacity
   #:history-count
   #:history-empty-p
   #:history-duplicate-policy
   ;; Access
   #:history-entry-at
   #:history-newest
   #:map-history
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
