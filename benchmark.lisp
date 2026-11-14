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

(defun large-history-text (index)
  "Return the distinct command text recorded at chronological INDEX."
  (cond
    ;; Only the oldest entry starts with \"docker\", so a prefix query for it
    ;; has to scan the whole ring.
    ((zerop index) "docker compose up -d legacy-stack")
    ((= (mod index 50) 7) (format nil "echo 作業ディレクトリ~D を確認しました" index))
    ((= (mod index 25) 3)
     (format nil "for f in src/*.lisp; do~%  wc -l \"$f\" # pass ~D~%done" index))
    (t
     (case (mod index 8)
       (0 (format nil "git commit -m \"fix issue ~D\"" index))
       (1 (format nil "cd ~~/src/project-~D" index))
       (2 (format nil "ls -la build/output-~D" index))
       (3 (format nil "nix build .#package-~D" index))
       (4 (format nil "make test-~D -j8" index))
       (5 (format nil "git checkout -b feature/topic-~D" index))
       (6 (format nil "grep -rn \"pattern~D\" src/" index))
       (7 (format nil "sbcl --script tools/run-~D.lisp" index))))))

(defun emit-large-history-result (label operations thunk)
  (sb-ext:gc :full t)
  (let ((start (get-internal-real-time))
        (start-bytes (sb-ext:get-bytes-consed)))
    (funcall thunk)
    (let* ((bytes (- (sb-ext:get-bytes-consed) start-bytes))
           (ticks (max 1 (- (get-internal-real-time) start)))
           (elapsed (/ ticks internal-time-units-per-second)))
      (format t "~&~A: ~D operations in ~,3F seconds (~,0F operations/second)~%"
              label operations elapsed (/ operations elapsed))
      (format t "~&~A: ~,1F bytes/operation~%" label (/ bytes operations)))))

(defun benchmark-large-history (&key (entries 100000))
  (let* ((start (get-internal-real-time))
         (history (history-kit:make-history :capacity entries))
         (newest-text (large-history-text (1- entries))))
    ;; HISTORY-MERGE takes its source newest first.
    (history-kit:history-merge
      history
      (loop for index from (1- entries) downto 0
            collect (history-kit:make-history-entry
                      (large-history-text index)
                      :timestamp (+ 3900000000 index)
                      :exit-code (if (zerop (mod index 13)) 1 0))))
    (format t "~&large history construction: ~D entries in ~,3F seconds~%"
            (history-kit:history-count history)
            (/ (- (get-internal-real-time) start) internal-time-units-per-second))
    (emit-large-history-result
      "100k snapshot newest entry via history-entries"
      200
      (lambda ()
        (dotimes (index 200)
          (declare (ignore index))
          (first (history-kit:history-entries history)))))
    (emit-large-history-result
      "100k full scan via history-entries + dolist"
      100
      (lambda ()
        (dotimes (index 100)
          (declare (ignore index))
          (let ((count 0))
            (dolist (entry (history-kit:history-entries history))
              (let ((text (history-kit:history-entry-text entry)))
                (when (and (>= (length text) 4) (string= "git " text :end2 4))
                  (incf count))))
            count))))
    (emit-large-history-result
      "100k autosuggest history-search :prefix :limit 1 (oldest match)"
      100
      (lambda ()
        (dotimes (index 100)
          (declare (ignore index))
          (history-kit:history-search history "docker" :limit 1))))
    (let ((query (subseq newest-text 0 6)))
      (emit-large-history-result
        "100k autosuggest history-search :prefix :limit 1 (newest match)"
        1000000
        (lambda ()
          (dotimes (index 1000000)
            (declare (ignore index))
            (history-kit:history-search history query :limit 1)))))
    (emit-large-history-result
      "100k history-search :contains case-insensitive (smartcase)"
      20
      (lambda ()
        (dotimes (index 20)
          (declare (ignore index))
          (history-kit:history-search history "build" :mode :contains))))
    (emit-large-history-result
      "100k history-search :contains case-sensitive"
      20
      (lambda ()
        (dotimes (index 20)
          (declare (ignore index))
          (history-kit:history-search
            history "build" :mode :contains :smartcase nil :case-sensitive t))))
    (emit-large-history-result
      "100k history-search :contains no match (subsequence-style query)"
      20
      (lambda ()
        (dotimes (index 20)
          (declare (ignore index))
          (history-kit:history-search history "gtcmfx" :mode :contains))))))

(progn
  (benchmark-hot-paths)
  (benchmark-large-history)
  (uiop:quit 0))
