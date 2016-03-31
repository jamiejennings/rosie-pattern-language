;; -*- Mode: Emacs-Lisp; -*- 
;;
;; rosie-development.el
;;
;; (c) 2016, Jamie A. Jennings
;;


;; rosie pattern language development in lua
(autoload 'lua-start-process "lua-interactive" "Lua" t)

(defvar rosie-process-buffer nil)

(defun switch-to-rosie (eob-p)
  "Switch to the rosie development process buffer.
With argument, position cursor at end of buffer."
  (interactive "P")
  (or (and rosie-process-buffer 
	   (get-buffer rosie-process-buffer)
	   (buffer-live-p (get-buffer rosie-process-buffer))
	   (get-buffer-process rosie-process-buffer))
      (error "No rosie process"))
  (pop-to-buffer rosie-process-buffer)
  (when eob-p
    (push-mark)
    (goto-char (point-max))))

(defvar rosie-home-dir "~/")

(defun rosie-start (rosie-home)
  (interactive "DRosie home directory: ")
  (if (eq rosie-home "")
      (setq rosie-home rosie-home-dir))
  (if (not (string-suffix-p "/" rosie-home))
      (set 'rosie-home (concat rosie-home "/")))
  (if (string-suffix-p "src/" rosie-home)
      (set 'rosie-home (substring rosie-home 0 -4))) ; chop off the "src/"
  (let ((rosie-program (concat rosie-home "run"))
	(rosie-switches '("-D")))
    (if (not (file-executable-p rosie-program))
	(error "Rosie executable does not exist or is not executable: %s" rosie-program))
    (let ((buf (apply 'lua-start-process "rosie development" rosie-program nil rosie-switches)))
      (setq rosie-process-buffer buf)
      (setq rosie-home-dir rosie-home)
      (switch-to-rosie t))))
  
(defun rosie ()
  (interactive)
  (if (and rosie-process-buffer 
	   (get-buffer rosie-process-buffer)
	   (buffer-live-p (get-buffer rosie-process-buffer)))
      (if (get-buffer-process rosie-process-buffer)
	  (switch-to-rosie t)
	(rosie-start rosie-home-dir))
    (call-interactively 'rosie-start)))

;; rosie pattern language (JAJ Tuesday, October 6, 2015)
(load "rpl-mode")
(add-to-list 'auto-mode-alist '("\\.rpl$" . rpl-mode))

(add-hook 'rpl-mode-hook '(lambda () 
			    (progn 
			      ;;(local-set-key "\C-\M-r" 'line-to-top)
			      (local-set-key "\C-cz" 'switch-to-lua)
			      (set-fill-column 100)
			      (auto-fill-mode 1))))


