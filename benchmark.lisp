;;;; Run through `nix run .#benchmark`, which packages this script with
;;;; cl-history-kit already on CL_SOURCE_REGISTRY via cl-nix-forge's
;;;; `lispScript` -- no source-registry bootstrap needed here.
(require :asdf)
(asdf:load-system "cl-history-kit")

(defun benchmark-hot-paths (&key (entries 4096) (steps 100000))
  (labels ((make-entries (count prefix)
             (loop for index below count
                   collect (history-kit:make-history-entry
                             (format nil "~A ~D" prefix index))))
           (make-populated-history (&key (duplicate-policy :remove))
             (let ((history
                     (history-kit:make-history
                       :capacity entries
                       :duplicate-policy duplicate-policy)))
               (history-kit:history-merge
                 history
                 (make-entries entries "git command"))
               history))
           (make-merge-sources (count)
             (loop for index below count
                   collect
                   (list (history-kit:make-history-entry
                           (format nil "new command ~D" index)))))
           (emit-result (label operations thunk)
             (let ((start (get-internal-real-time)))
               (funcall thunk)
               (let* ((ticks (max 1 (- (get-internal-real-time) start)))
                      (elapsed (/ ticks internal-time-units-per-second))
                      (rate (/ operations elapsed)))
                 (format
                   t
                   "~&~A: ~D operations in ~,3F seconds (~,0F operations/second)~%"
                   label
                   operations
                   elapsed
                   rate)))))
    (let* ((lookup-steps (max 10 (floor steps 1000)))
           (recording-steps (max 10 (floor steps 100)))
           (history (make-populated-history))
           ;; Construct inputs before timing so this loop measures merge work only.
           (merge-sources (make-merge-sources lookup-steps)))
      (emit-result
        "end-to-end prefix lookup (fresh navigation)"
        lookup-steps
        (lambda ()
          (dotimes (index lookup-steps)
            (declare (ignore index))
            (history-kit:history-reset-navigation history)
            (history-kit:history-previous history "git"))))
      (history-kit:history-reset-navigation history)
      (history-kit:history-previous history "git" :wrap t)
      (emit-result
        "cached navigation (direct public call)"
        steps
        (lambda ()
          (dotimes (index steps)
            (declare (ignore index))
            (history-kit:history-previous history "git" :wrap t))))
      (let ((merge-history-target (make-populated-history)))
        (emit-result
          "isolated capacity-bounded merge (prebuilt entries)"
          lookup-steps
          (lambda ()
            (dolist (source merge-sources)
              (history-kit:history-merge merge-history-target source)))))
      (let ((recording-history
              (make-populated-history :duplicate-policy :keep)))
        (emit-result
          "full :KEEP recording"
          recording-steps
          (lambda ()
            (dotimes (index recording-steps)
              (declare (ignore index))
              (history-kit:history-add recording-history "recorded command"))))))))

(progn
  (benchmark-hot-paths)
  (uiop:quit 0))
