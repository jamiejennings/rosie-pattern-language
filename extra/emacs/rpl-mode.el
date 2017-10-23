; -*- Mode: Emacs-Lisp; -*-                                           
;;
;; rpl-mode.el      An editing mode for RPL built from scratch
;;
;; © Copyright IBM Corporation 2017.
;; LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
;; AUTHOR: Jamie A. Jennings

(defvar *rpl-mode-verbose* t)

(defun rpl-maybe-message (msg)
  (if *rpl-mode-verbose*
      (message (concat "rpl-mode: " msg))))

(defvar rpl-mode-hook nil)

(defvar rpl-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-j" 'newline-and-indent)
    map)
  "rpl major mode key map")

(defvar rpl-declaration-keywords
      (regexp-opt '("import" "package" "rpl") 'words))

(defvar rpl-binding-keywords
      (regexp-opt '("local" "alias" "grammar" "end") 'words))

(defvar rpl-some-space "[ \t]+")
(defvar rpl-any-space "[ \t]*")

(defvar rpl-optional-comment "\\s *\\(--.*\\)?$")

(defvar rpl-font-lock-keywords-basic
  (list
   `(,rpl-binding-keywords (1 font-lock-keyword-face))
   ))

(defvar rpl-font-lock-keywords-bindings
      (list
       `(,(concat "^" rpl-any-space                          ; fresh line, any amount of whitespace
		  "\\(?:\\(?:\\sw+\\)" rpl-some-space "\\)*" ; any series of words
		  "\\(\\sw+\\)"		                     ; identifier being bound
		  rpl-any-space "[=]" rpl-any-space	     ; the key element is the '=' sign
		  )
	 (1 font-lock-variable-name-face))))

(defvar rpl-font-lock-keywords-declarations
      (list
      `(,(concat "^" rpl-any-space     ; fresh line, any amount of whitespace
		  "\\(\\<package\\>\\|\\<rpl\\>\\)"
		  rpl-some-space
		  "\\(\\S-+\\)"		; package name or rpl version spec
		  )
	(1 font-lock-preprocessor-face)) ; (2 font-lock-negation-char-face))
       ;; below is an "anchored match": (anchor-pat (item-pat pre-form post-form face-spec))
       `(,(concat "^" rpl-any-space
		  "\\(\\<import\\>\\)"
		  rpl-some-space)
	 ;; above is the anchor, and scope is from end of anchor to the end of the line
	 ;; pre-form below moves to start of line so we catch the anchor, i.e. "import"
	 ("\\<as\\>\\|\\<import\\>" (beginning-of-line) nil (0 font-lock-preprocessor-face)))
       ))

(defvar rpl-function-regexp "\\b\\([[:alpha:]][[:alnum:]]*\\):\\S ")

(defvar rpl-font-lock-functions
      (list
       (list rpl-function-regexp `(1 font-lock-function-name-face))))

(defvar rpl-font-lock-keywords-ALL
      (append rpl-font-lock-keywords-basic
	      rpl-font-lock-keywords-bindings
              rpl-font-lock-keywords-declarations
	      rpl-font-lock-functions))
;      "Syntax highlighting for rpl mode")

(defvar rpl-font-lock-keywords rpl-font-lock-keywords-ALL)
;  "Default highlighting expressions for rpl mode")

;; ----------------------------------------------------------------------------------------


(defun rpl-goto-previous-nonblank-line ()
  "Puts the point at the first previous line that is not blank.
Returns the point, or nil if it reached the beginning of the buffer"
  (catch 'found
    (beginning-of-line)
    (while t
      (if (bobp) (throw 'found nil))
      (forward-char -1)
      (beginning-of-line)
      (if (not (looking-at rpl-optional-comment)) (throw 'found (point))))))

(defun rpl-goto-next-nonblank-line ()
  "Puts the point at the first next line that is not blank.
Returns the point, or nil if it reached the end of the buffer"
  (catch 'found
    (end-of-line)
    (while t
      (forward-line)
      (if (eobp) (throw 'found nil))
      (beginning-of-line)
      (if (not (looking-at rpl-optional-comment)) (throw 'found (point))))))

(defvar rpl-binding-regexp
      (concat rpl-any-space
	      "\\(\\sw+" rpl-some-space "\\)*" ; skip binding modifiers before identifier name
	      "\\("
	      "\\sw+" rpl-any-space "=" rpl-any-space
	      "\\|"
	      "\\<grammar\\>"
	      "\\)"))

(defvar rpl-end-regexp
      (concat rpl-any-space "\\<end\\>\\(" rpl-some-space "\\|$\\)"))

(defvar rpl-grammar-regexp
      (concat rpl-any-space
	      "\\(\\sw+" rpl-some-space "\\)*" ; skip any binding modifiers before "grammar"
	      "\\<grammar\\>\\(" rpl-some-space "\\|$\\)"))

(defvar rpl-declaration-regexp
      (concat rpl-any-space
	      rpl-declaration-keywords
	      rpl-some-space))

(defun rpl-find-previous-binding ()
  "Returns a buffer position on the line containing the previous binding, and
nil if the previous rpl statement was not a binding"
  (save-excursion
    (cond ((rpl-goto-previous-nonblank-line)
	   (let ((has-binding (re-search-forward rpl-binding-regexp (line-end-position) t)))
	     (cond (has-binding (match-end 0))
		   ((looking-at rpl-end-regexp) nil)
		   ((looking-at rpl-grammar-regexp) nil)
		   ((looking-at rpl-declaration-regexp) nil)
		   (t
		    (rpl-find-previous-binding)))))
	  (t ;; there was no previous nonblank line
	   nil))))

;; (defun rpl-continues-binding-p ()
;;   "Returns nil if current line cannot continue a binding started on a previous line, 
;; and the buffer position of the text after the binding '=' sign otherwise"
;;   (save-excursion
;;     (beginning-of-line)
;;     (cond ((looking-at rpl-binding-regexp) nil) ; current line starts new binding
;; 	  (t
;; 	   (rpl-find-previous-binding)))))


;; (rpl-goto-previous-nonblank-line)
;; 	   (let ((has-binding (re-search-forward rpl-binding-regexp (line-end-position) t)))
;; 	     (cond (has-binding (match-end 0))
;; 		   ((looking-at rpl-end-regexp) nil)
;; 		   ((looking-at rpl-grammar-regexp) nil)
;; 		   ((looking-at rpl-declaration-regexp) nil)
;; 		   (t
;; 		    (rpl-continues-binding-p)))))
;; 	  (t ;; there was no previous nonblank line
;; 	   nil))))
  
;; rpl indentation rules:
;;
;; bobp -> column 0 (beginning of buffer)
;; current line is 'end' -> de-ident relative to previous line (ending a grammar block)
;; current line is a comment -> indent to same as previous line
;; previous line was 'grammar' -> indent relative to previous line
;; current line is NOT blank -> 
;;   could continue a binding -> indent to first non-space after '=' sign (to continue the definition)
;;   else indent to same as previous line
;; these collapse into a single ELSE:
;;   previous line was 'end' -> indent to same as previous line
;;   binding start OR file-level decl -> indent to same as previous line
;;   else -> indent to previous line

(defvar rpl-default-indentation 3
  "Number of spaces to indent in rpl-mode")

(defun rpl-indent-line ()
  (interactive)
  (let ((blank-line-regexp (concat rpl-any-space "\\(--.*\\)?" "$")) ; ignore comments
	(comment-line-regexp (concat rpl-any-space "--.*$"))
	(amount 0)
	(existing-amount (current-indentation)))
    (save-excursion
      (beginning-of-line)
      (cond ((save-excursion (not (rpl-goto-previous-nonblank-line))) ; is there a non-comment nonblank line?
	     (rpl-maybe-message "Essentially at bob")
	     (indent-line-to 0))
	    ((looking-at rpl-end-regexp) ; current line is "end"
	     (progn
	       (save-excursion
		 (rpl-goto-previous-nonblank-line)
		 (setq amount (max (- (current-indentation) rpl-default-indentation) 0))
		 (rpl-maybe-message "Looking at end"))))
	    ((looking-at comment-line-regexp) ; current line is comment
	     (progn
	       (save-excursion
		 (rpl-maybe-message "Looking at comment line")
		 (forward-line -1)
		 (setq amount (current-indentation)))))
	    ((save-excursion (rpl-goto-previous-nonblank-line) (looking-at rpl-grammar-regexp))
	     (rpl-maybe-message "Previous line was grammar")
	     (setq amount (+ rpl-default-indentation
			     (save-excursion (rpl-goto-previous-nonblank-line)
					     (current-indentation)))))
	    ((looking-at rpl-binding-regexp)
	     (let ((continue-pos (rpl-find-previous-binding)))
	       (cond (continue-pos
		      (rpl-maybe-message "On new binding line, lining up with previous binding")
		      (setq amount (save-excursion (goto-char continue-pos) (current-indentation))))
		     (t
		      (rpl-maybe-message "On new binding line, no previous one")
		      (setq amount (save-excursion (forward-line -1) (current-indentation)))))))
	    ((not (looking-at blank-line-regexp))
	     (let ((continue-pos (rpl-find-previous-binding)))
	       (cond (continue-pos
		      (rpl-maybe-message "On nonblank line that can continue a binding")
		      (setq amount (save-excursion (goto-char continue-pos) (current-column))))
		     (t 
		      (rpl-maybe-message "On nonblank line that does NOT continue a binding")
		      (save-excursion
			(forward-line -1)
			(setq amount (current-indentation)))))))
	    (t
	     (save-excursion
	       (rpl-goto-previous-nonblank-line)
	       (cond ((looking-at rpl-end-regexp) ; previous line is "end"
		      (rpl-maybe-message "Previous line was end")
		      (setq amount (current-indentation)))
		     ))))
      (if (not (= amount existing-amount))
	  (indent-line-to amount)))
    ;; If the point is in the indent area, move it past the indent
    ;;
    (if (< (current-column) (current-indentation))
	(forward-whitespace 1))))

(defvar rpl-mode-syntax-table
  (let ((syntax-table (make-syntax-table)))
    (modify-syntax-entry ?_ "w" syntax-table)     ; _ is a word constituent
    (modify-syntax-entry ?. "_" syntax-table)     ; . is a word constituent, e.g. `common.int'
    (modify-syntax-entry ?- ". 12" syntax-table)  ; This is critical for getting comments highlighted!
    (modify-syntax-entry ?\n ">" syntax-table)    ; This is critical for getting comments highlighted!
    syntax-table))
    
(defun rpl-mode ()
  "Major mode for editing Rosie Pattern Language files"
  (interactive)
  (kill-all-local-variables)
  (set-syntax-table rpl-mode-syntax-table)
  ;(use-local-map rpl-mode-map)
  (set (make-local-variable 'font-lock-defaults) '(rpl-font-lock-keywords))
  (set (make-local-variable 'indent-line-function) 'rpl-indent-line)  
  (set (make-local-variable 'comment-start) "--")
  (set (make-local-variable 'comment-start-skip) "--")
  (setq comment-column 60)
  (setq major-mode 'rpl-mode)
  (setq mode-name "rpl")
  (run-hooks 'rpl-mode-hook))

(provide 'rpl-mode)
(rpl-maybe-message "major mode loaded")

(message "Reminder: rpl-mode still needs setq statements replaced by defconst")

	       
