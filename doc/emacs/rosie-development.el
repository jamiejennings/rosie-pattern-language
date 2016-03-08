;; -*- Mode: Emacs-Lisp; -*- 
;;
;; rosie-development.el
;;
;; (c) 2016, Jamie A. Jennings
;;


;; rosie pattern language development in lua
(autoload 'lua-start-process "lua-interactive" "Lua" t)
(defun rosie (rosie-home)
  (interactive "D")
  (if (not (string-suffix-p "/" rosie-home))
      (set 'rosie-home (concat rosie-home "/")))
  (if (string-suffix-p "src/" rosie-home)
      (set 'rosie-home (substring rosie-home 0 -4))) ; chop off the "src/"
  (let ((rosie-program (concat rosie-home "run"))
	(rosie-switches '("-D")))
    (if (not (file-executable-p rosie-program))
	(error "Rosie executable does not exist or is not executable: %s" rosie-program))
    (apply 'lua-start-process "rosie development" rosie-program nil rosie-switches)
    (switch-to-lua t)))
  

;; rosie pattern language (JAJ Tuesday, October 6, 2015)
(load "rpl-mode")
(add-to-list 'auto-mode-alist '("\\.rpl$" . rpl-mode))

(add-hook 'rpl-mode-hook '(lambda () 
			    (progn 
			      ;;(local-set-key "\C-\M-r" 'line-to-top)
			      (local-set-key "\C-cz" 'switch-to-lua)
			      (set-fill-column 100)
			      (auto-fill-mode 1))))


