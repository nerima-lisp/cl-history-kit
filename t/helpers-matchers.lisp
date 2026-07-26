;;;; t/helpers-matchers.lisp
;;;;
;;;; Domain-specific expectations and builders shared by every spec file, so
;;;; the specs read in the vocabulary of the library ("records these texts",
;;;; "finds these texts") instead of raw list-predicate soup.
(in-package #:cl-history-kit/test)

(defmatcher :to-record-texts (actual expected)
  "Passes when the history ACTUAL holds exactly the single EXPECTED list of
texts, newest first."
  (let ((expected-texts (first expected))
        (texts (history-entry-texts (history-entries actual))))
    (values (equal texts expected-texts)
            (list :texts texts)
            (list :expected expected-texts))))

(defmatcher :to-have-texts (actual expected)
  "Passes when the entry list ACTUAL -- a search result, say -- carries exactly
the single EXPECTED list of texts, in order."
  (let ((expected-texts (first expected))
        (texts (history-entry-texts actual)))
    (values (equal texts expected-texts)
            (list :texts texts)
            (list :expected expected-texts))))

(defun history-of (texts &rest options)
  "Build a history holding TEXTS, which are listed newest first.

OPTIONS are passed straight to MAKE-HISTORY, so a spec can vary capacity or
duplicate policy without restating the seeding loop."
  (let ((history (apply #'make-history options)))
    (dolist (text (reverse texts) history)
      (history-add history text))))

;;; A deliberately small alphabet: short commands drawn from it collide often,
;;; so duplicate handling, prefix matching, and capacity eviction are all
;;; exercised by ordinary generated input rather than only by rare edge cases.
(defparameter +command-alphabet+ "abc -")

(defun gen-command-text (&key (min-length 1) (max-length 8))
  (gen-string :alphabet +command-alphabet+
              :min-length min-length
              :max-length max-length))
