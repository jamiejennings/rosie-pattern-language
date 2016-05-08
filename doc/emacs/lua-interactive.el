;;; lua-interactive.el -- extends lua-mode.el 

(require 'lua-mode)
(provide 'lua-interactive)

(defvar lua-mode-map (make-sparse-keymap))

(define-key lua-mode-map "\C-cz" 'switch-to-lua)
(define-key lua-mode-map "\C-\M-a" 'lua-beginning-of-proc)
(define-key lua-mode-map "\C-\M-e" 'lua-end-of-proc)
(define-key lua-mode-map "\C-\M-q" 'lua-indent-proc)

(define-key lua-mode-map "\C-c\C-c" 'lua-send-proc-and-go)
(define-key lua-mode-map "\C-c\C-r" 'lua-send-region-and-go)

(define-key lua-mode-map "\C-c\l" 'lua-send-buffer)
(define-key lua-mode-map "\C-c\C-l" 'lua-send-buffer-and-go)

(defun lua-surrounding-proc ()
  "Return the beginning and end marks of the proc surrounding point"
  (let (beg end (start (point)))
    (save-excursion
      (lua-beginning-of-proc)
      (setq beg (point))
      (lua-end-of-proc)
      (setq end (point)))
    (if (and (>= start beg)
	     (<= start end))
	(cons beg end)
      (error "Not inside a Lua function definition"))))

(defun lua-indent-proc ()
  (interactive)
  (let* ((region (lua-surrounding-proc))
	 (st (car region))
	 (fin (cdr region))
	 (ok (if (not (and (pos-visible-in-window-p st)
			   (pos-visible-in-window-p fin)))
		 (y-or-n-p "Region to indent extends beyond what is visible in the window. Proceed?")
	       t)))
    (if ok
	(indent-region st fin)
      (message nil))))

(defun lua-send-buffer-and-go ()
  (interactive)
  (lua-send-buffer)
  (switch-to-lua t))

;; I didn't like lua-send-proc from lua-mode.el  (JAJ Thursday, April 7, 2016)
(defun lua-send-proc-and-go ()
  (interactive)
  (let ((range (lua-surrounding-proc)))
    (lua-send-region (car range) (cdr range))
    (switch-to-lua t)))

(defun lua-send-region-and-go ()
  (interactive)
  (lua-send-region (point) (mark))
  (switch-to-lua t)
  )

;(define-key scheme-mode-map "\C-ce"    'scheme48-send-definition)
;(define-key scheme-mode-map "\C-c\C-e" 'scheme48-send-definition-and-go)
;(define-key scheme-mode-map "\C-cr"    'scheme48-send-region)
;(define-key scheme-mode-map "\C-c\C-r" 'scheme48-send-region-and-go)


(defun switch-to-lua (eob-p)
  "Switch to the lua process buffer.
With argument, position cursor at end of buffer."
  (interactive "P")
  (or (and lua-process-buffer 
	   (get-buffer lua-process-buffer)
	   (buffer-live-p (get-buffer lua-process-buffer))
	   (get-buffer-process lua-process-buffer))
      (lua-start-process lua-default-application))
  (pop-to-buffer lua-process-buffer)
  (when eob-p
    (push-mark)
    (goto-char (point-max))))


;(defun scheme48-send-region (start end)
;  "Send the current region to the inferior Scheme process."
;  (interactive "r")
;  (comint-send-string (scheme-proc)
;                      (concat ",from-file "
;                              (enough-scheme-file-name
;                               (buffer-file-name (current-buffer)))
;                              "\n"))
;  (comint-send-region (scheme-proc) start end)
;  (comint-send-string (scheme-proc) " ,end\n"))

; This assumes that when you load things into Scheme 48, you type
; names of files in your home directory using the syntax "~/".
; Similarly for current directory.  Maybe we ought to send multiple
; file names to Scheme and let it look at all of them.

;(defun enough-scheme-file-name (file)
;  (let* ((scheme-dir
;          (save-excursion
;            (set-buffer scheme-buffer)
;            (expand-file-name default-directory)))
;         (len (length scheme-dir)))
;    (if (and (> (length file) len)
;             (string-equal scheme-dir (substring file 0 len)))
;        (substring file len)
;        (if *scheme48-home-directory-kludge*
;            (let* ((home-dir (expand-file-name "~/"))
;                   (len (length home-dir)))
;              (if (and (> (length file) len)
;                       (string-equal home-dir (substring file 0 len)))
;                  (concat "~/" (substring file len))
;                  file))
;            file))))

;(defvar *scheme48-home-directory-kludge* t)

;(defun scheme48-send-definition (losep)
;  "Send the current definition to the inferior Scheme48 process."
;  (interactive "P")
;  (save-excursion
;   (end-of-defun)
;   (let ((end (point)))
;     (beginning-of-defun)
;     (if losep
;         (let ((loser "/tmp/s48lose.tmp"))
;           (write-region (point) end loser)
;           (scheme48-load-file loser))
;         (scheme48-send-region (point) end)))))

;(defun scheme48-send-last-sexp ()
;  "Send the previous sexp to the inferior Scheme process."
;  (interactive)
;  (scheme48-send-region (save-excursion (backward-sexp) (point)) (point)))

;(defun scheme48-send-region-and-go (start end)
;  "Send the current region to the inferior Scheme48 process,
;and switch to the process buffer."
;  (interactive "r")
;  (scheme48-send-region start end)
;  (switch-to-scheme t))

;(defun scheme48-send-definition-and-go (losep)
;  "Send the current definition to the inferior Scheme48,
;and switch to the process buffer."
;  (interactive "P")
;  (scheme48-send-definition losep)
;  (switch-to-scheme t))

