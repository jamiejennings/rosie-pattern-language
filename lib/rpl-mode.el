;; -*- Mode: Emacs-Lisp; -*- 
;;
;; rpl-mode.el --- a major-mode for editing Rosie Pattern Language files
;;
;; (c) 2015, Jamie A. Jennings
;;

;; This file is NOT part of Emacs.

(defconst rpl-version "2015-003"
  "rpl mode version number.")

;; Keywords: languages, processes, tools

;; To see all the keybindings for RPL mode, look at `rpl-setup-keymap'
;; or start `rpl-mode' and type `\C-h m'.
;;
;; You can customize the keybindings either by setting `rpl-prefix-key'
;; or by putting the following in your .emacs
;;      (setq rpl-mode-map (make-sparse-keymap))
;; and
;;      (define-key rpl-mode-map <your-key> <function>)
;; for all the functions you need.


(require 'comint)

;; Local variables
(defgroup rpl nil
  "Major mode for editing rpl code."
  :prefix "rpl-"
  :group 'languages)

;(defcustom rpl-default-application "rpl"
;  "Default application to run in rpl subprocess."
;  :type 'string
;  :group 'rpl)
;
;(defcustom rpl-default-command-switches (list "-i")
;  "Command switches for `rpl-default-application'.
;Should be a list of strings."
;  :type '(repeat string)
;  :group 'rpl)
;
;(defcustom rpl-always-show t
;  "*Non-nil means display rpl-process-buffer after sending a command."
;  :type 'boolean
;  :group 'rpl)
;
;(defvar rpl-process nil
;  "The active Rpl subprocess")
;
;(defvar rpl-process-buffer nil
;  "Buffer used for communication with Rpl subprocess")

(defvar rpl-mode-map nil
  "Keymap used with rpl-mode.")

(defvar rpl-electric-flag t
"If t, electric actions (like automatic reindentation)  will happen when an electric
 key like `{' is pressed") 
(make-variable-buffer-local 'rpl-electric-flag)

(defcustom rpl-prefix-key "\C-c"
  "Prefix for all rpl-mode commands."
  :type 'string
  :group 'rpl)

(defcustom rpl-prompt-regexp "[^\n]*\\(>[\t ]+\\)+$"
  "Regexp which matches the Rpl program's prompt."
  :group 'rpl
  :type  'regexp
  )

(defvar rpl-mode-hook nil
  "Hooks called when rpl mode fires up.")

(defvar rpl-region-start (make-marker)
  "Start of special region for rpl communication.")

(defvar rpl-region-end (make-marker)
  "End of special region for rpl communication.")

(defvar rpl-indent-level 3
  "Amount by which rpl subexpressions are indented.")

(defvar rpl-mode-menu (make-sparse-keymap "rpl")
  "Keymap for rpl-mode's menu.")

(defvar rpl-font-lock-keywords
  (eval-when-compile
    (list
     ;;
     ;; Alias name declarations.
     '("^[ \t]*\\<\\(\\(alias[ \t]+\\)?alias\\)\\>[ \t]+\\(\\(\\sw:\\|\\sw\\.\\|\\sw_\\|\\sw\\)+\\)"
       (1 font-lock-keyword-face) (3 font-lock-function-name-face nil t))

     ;; Grammar declarations that start with an alias rule
     '(;;"^[ \t]*\\<\\(\\(grammar[ \t]+\\)?grammar\\)\\>[ \t]+\\<\\(\\(alias[ \t]+\\)?alias\\)\\>[ \t]+\\(\\(\\sw:\\|\\sw\\.\\|\\sw_\\|\\sw\\)+\\)"
       "^[ \t]*\\(grammar\\)[ \t]+\\(alias\\)[ \t]+\\(\\(\\w\\|:\\|\\.\\|_\\)+\\)"
       (1 font-lock-keyword-face) (2 font-lock-keyword-face) (3 font-lock-function-name-face nil t))

     ;; Grammar declarations that do not start with an alias rule
     '("^[ \t]*\\<\\(\\(grammar[ \t]+\\)?grammar\\)\\>[ \t]+\\(\\(\\sw:\\|\\sw\\.\\|\\sw_\\|\\sw\\)+\\)"
       (1 font-lock-keyword-face) (3 font-lock-function-name-face nil t))

     ;; Handle pattern names in assignments
     '(;; "\\(\\(\\sw:\\|\\sw\\.\\|\\sw_\\|\\sw\\)+\\)[ \t]*=[ \t]*\\>"
       "^[ \t]*\\(\\(\\sw:\\|\\sw\\.\\|\\sw_\\|\\sw\\)+\\)[ \t]*=[ \t]*"
       (1 font-lock-function-name-face nil t))

     ;; This didn't quite work, e.g. in a line like this:
     ;;      foo = "--" bar baz
     ;; 'bar baz' would be highlighted in comment face.
     ;; Single line comments
;     `("\\(--.*$\\)"
;       (1 font-lock-comment-face nil t))

     ;; Keywords.
      (concat "\\<"
              (regexp-opt '("alias"
			    "enumerate"
			    "range"
			    "discard"
			    "produce"
			    "grammar"
			    "end"
			    )
			  t)
              "\\>")

     "Default expressions to highlight in rpl mode.")))

;(defvar rpl-imenu-generic-expression
;  '((nil "^[ \t]*\\(?:local[ \t]+\\)?function[ \t]+\\(\\(\\sw:\\|\\sw_\\|\\sw\\.\\|\\sw\\)+\\)" 1))
;  "Imenu generic expression for rpl-mode.  See `imenu-generic-expression'.")

(defvar rpl-mode-abbrev-table nil
  "Abbreviation table used in rpl-mode buffers.")

;(defvar rpl-sexp-alist '(("then" . "end")
;                        ("function" . "end")
;                        ("do" . "end")))

(define-abbrev-table 'rpl-mode-abbrev-table
  '(
        ("end" "end" rpl-indent-line 0)
;        ("else" "else" rpl-indent-line 0)
;        ("elseif" "elseif" rpl-indent-line 0)
        ))

(defconst rpl-indent-whitespace " \t"
  "Character set that constitutes whitespace for indentation in rpl.")

;(eval-and-compile
;  (defalias 'rpl-make-temp-file
;    (if (fboundp 'make-temp-file)
;        'make-temp-file
;      (lambda (prefix &optional dir-flag) ;; Simple implementation
;        (expand-file-name
;         (make-temp-name prefix)
;         (if (fboundp 'temp-directory)
;             (temp-directory)
;           temporary-file-directory))))))

(eval-and-compile
  (if (not (fboundp 'replace-in-string)) ;GNU emacs doesn't have it
      (defun replace-in-string  (string regexp newtext &optional literal)
	(replace-regexp-in-string regexp newtext string nil literal))))

;;;###autoload
(defun rpl-mode ()
  "Major mode for editing rpl code.
The following keys are bound:
\\{rpl-mode-map}
"
  (interactive)
  (let ((switches nil)
                  s)
    (kill-all-local-variables)
    (setq major-mode 'rpl-mode)
    (setq mode-name "rpl")
    (setq comint-prompt-regexp rpl-prompt-regexp)
    (make-local-variable 'rpl-default-command-switches)
    (set (make-local-variable 'indent-line-function) 'rpl-indent-line)
    (set (make-local-variable 'comment-start) "--")
;    (set (make-local-variable 'comment-end) "")
    (set (make-local-variable 'comment-start-skip) "--")
    (set (make-local-variable 'font-lock-defaults)
                        '(rpl-font-lock-keywords nil nil ((?_ . "w"))))
;    (set (make-local-variable 'imenu-generic-expression)
;                        rpl-imenu-generic-expression)
         (setq local-abbrev-table rpl-mode-abbrev-table)
         (abbrev-mode 1)
    (make-local-variable 'rpl-default-eval)
    (or rpl-mode-map
                  (rpl-setup-keymap))
    (use-local-map rpl-mode-map)
    (set-syntax-table (copy-syntax-table))
;    (modify-syntax-entry ?+ ".")
    (modify-syntax-entry ?- ". 12")  ; This is critical for getting comments highlighted!
;    (modify-syntax-entry ?* ".")
;    (modify-syntax-entry ?/ ".")
;    (modify-syntax-entry ?^ ".")
    ;; This might be better as punctuation, as for C, but this way you
    ;; can treat table index as symbol.
    (modify-syntax-entry ?. "_")	; e.g. `io.string'
    (modify-syntax-entry ?> ")<")
    (modify-syntax-entry ?< "(>")
;    (modify-syntax-entry ?= ".")
;    (modify-syntax-entry ?~ ".")
    (modify-syntax-entry ?\n ">")  ; This is critical for getting comments highlighted!
;    (modify-syntax-entry ?\' "\"")
;    (modify-syntax-entry ?\" "\"")	; Do we need this? Appears not.
    ;; _ needs to be part of a word, or the regular expressions will
    ;; incorrectly regognize end_ to be matched by "\\<end\\>"!
    (modify-syntax-entry ?_ "w")
;    (if (and rpl-using-xemacs
;             (featurep 'menubar)
;             current-menubar
;             (not (assoc "rpl" current-menubar)))
;        (progn
;          (set-buffer-menubar (copy-sequence current-menubar))
;          (add-menu nil "rpl" rpl-xemacs-menu)))
;    ;; Append rpl menu to popup menu for XEmacs.
;    (if (and rpl-using-xemacs (boundp 'mode-popup-menu))
;        (setq mode-popup-menu
;              (cons (concat mode-name " Mode Commands") rpl-xemacs-menu)))

    ;; hideshow setup
;    (unless (assq 'rpl-mode hs-special-modes-alist)
;      (add-to-list 'hs-special-modes-alist
;                   `(rpl-mode  
;                     ,(regexp-opt (mapcar 'car rpl-sexp-alist) 'words);start
;                     ,(regexp-opt (mapcar 'cdr rpl-sexp-alist) 'words) ;end
;                     nil rpl-forward-sexp)))
    (run-hooks 'rpl-mode-hook)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rpl$" . rpl-mode))

(defun rpl-setup-keymap ()
  "Set up keymap for rpl mode.
If the variable `rpl-prefix-key' is nil, the bindings go directly
to `rpl-mode-map', otherwise they are prefixed with `rpl-prefix-key'."
  (setq rpl-mode-map (make-sparse-keymap))
  (define-key rpl-mode-map [menu-bar rpl-mode]
    (cons "rpl" rpl-mode-menu))
  (define-key rpl-mode-map "}" 'rpl-electric-match)
  (define-key rpl-mode-map "]" 'rpl-electric-match)
  (define-key rpl-mode-map ")" 'rpl-electric-match)
  (define-key rpl-mode-map ">" 'rpl-electric-match)
  (let ((map (if rpl-prefix-key
		 (make-sparse-keymap)
	       rpl-mode-map)))
         ;; communication
;         (define-key map "\M-[" 'rpl-beginning-of-proc)
;         (define-key map "\M-]" 'rpl-end-of-proc)
         (define-key map "\C-c" 'comment-region)
	 (define-key map "\C-l" 'rpl-send-buffer)
;	 (define-key map "\C-f" 'rpl-search-documentation)
         (if rpl-prefix-key
                  (define-key rpl-mode-map rpl-prefix-key map))
         ))

(defun rpl-electric-match (arg)
  "Insert character and adjust indentation."
  (interactive "P")
  (insert-char last-command-event (prefix-numeric-value arg))
  (if rpl-electric-flag 
      (rpl-indent-line))
  (blink-matching-open))


(defun rpl-syntax-status ()
  "Returns the syntactic status of the character after the point."
  (parse-partial-sexp (save-excursion (beginning-of-line) (point))
		      (point)))


(defun rpl-string-p ()
  "Returns true if the point is in a string."
  (elt (rpl-syntax-status) 3))

(defun rpl-comment-p ()
  "Returns true if the point is in a comment."
    (elt (rpl-syntax-status) 4))

(defun rpl-comment-or-string-p ()
  "Returns true if the point is in a comment or string."
  (let ((parse-result (rpl-syntax-status)))
    (or (elt parse-result 3) (elt parse-result 4))))

(defun rpl-indent-line ()
  "Indent current line for rpl mode.
Return the amount the indentation changed by."
  (let ((indent (max 0 (- (rpl-calculate-indentation nil)
			  (rpl-calculate-indentation-left-shift))))
	beg shift-amt
	(case-fold-search nil)
	(pos (- (point-max) (point))))
    (beginning-of-line)
    (setq beg (point))
    (skip-chars-forward rpl-indent-whitespace)
    (setq shift-amt (- indent (current-column)))
    (when (not (zerop shift-amt))
      (delete-region beg (point))
      (indent-to indent))
    ;; If initial point was within line's indentation,
    ;; position after the indentation.  Else stay at same point in text.
    (if (> (- (point-max) pos) (point))
	(goto-char (- (point-max) pos)))
    shift-amt
    indent))

(defun rpl-find-regexp (direction regexp &optional limit ignore-p)
  "Searches for a regular expression in the direction specified.
Direction is one of 'forward and 'backward.
By default, matches in comments and strings are ignored, but what to ignore is
configurable by specifying ignore-p. If the regexp is found, returns point
position, nil otherwise.
ignore-p returns true if the match at the current point position should be
ignored, nil otherwise."
  (let ((ignore-func (or ignore-p 'rpl-comment-or-string-p))
	(search-func (if (eq direction 'forward)
			 're-search-forward 're-search-backward))
	(case-fold-search nil))
    (catch 'found
      (while (funcall search-func regexp limit t)
	(if (not (funcall ignore-func))
	    (throw 'found (point)))))))

(defun rpl-backwards-to-block-begin-or-end ()
  "Move backwards to nearest block begin or end.  Returns nil if not successful."
  (interactive)
  (rpl-find-regexp 'backward rpl-block-regexp))


(defconst rpl-block-regexp
  (eval-when-compile
    ;; This is the code we used to generate the regexp:
    (concat
     "\\(\\<"
     (regexp-opt '("grammar" "enumerate" "transform" "end") t)
     "\\>\\)\\|"
     (regexp-opt '("<" "{" "(" "[" "]" ")" "}" ">") t))
    ))

(defconst rpl-block-token-alist
  ;; The absence of "else" is deliberate. This construct in a way both
  ;; opens and closes a block. As a result, it is difficult to handle
  ;; cleanly. It is also ambiguous - if we are looking for the match
  ;; of "else", should we look backward for "then/elseif" or forward
  ;; for "end"?
  ;; Maybe later we will find a way to handle it.
  '(("grammar"  "\\<end\\>"                                   open)
    ("enumerate" "\\<end\\>"                                  open)
    ("transform" "\\<end\\>"                                  open)
    ("<"        ">"                                           open)
    ("{"        "}"                                           open)
    ("["        "]"                                           open)
    ("("        ")"                                           open)
    ("end"      "\\<\\(grammar\\|enumerate\\|transform\\)\\>"            close)
    (">"        "<"                                           close)
    ("}"        "{"                                           close)
    ("]"        "\\["                                         close)
    (")"        "("                                           close)))


(defconst rpl-indentation-modifier-regexp
    ;; The absence of else is deliberate, since it does not modify the
    ;; indentation level per se. It only may cause the line, in which the
    ;; else is, to be shifted to the left.
    ;; This is the code we used to generate the regexp:
    (concat
     "\\("
     "\\<"
     (regexp-opt '("grammar" "enumerate" "transform") t)
     "\\>\\|"
     (regexp-opt '("{" "(" "<"))
     "\\)\\|\\("
     "\\<"
     (regexp-opt '("end") t)
     "\\>\\|"
     (regexp-opt '(">" ")" "}"))
     "\\)")
    )

(defun rpl-find-matching-token-word (token search-start)
  (let* ((token-info (assoc token rpl-block-token-alist))
         (match (car (cdr token-info)))
         (match-type (car (cdr (cdr token-info))))
         (search-direction (if (eq match-type 'open) 'forward 'backward)))
    ;; if we are searching forward from the token at the current point
    ;; (i.e. for a closing token), need to step one character forward
    ;; first, or the regexp will match the opening token.
    (if (eq match-type 'open) (forward-char 1))
    (if search-start (goto-char search-start))
    (catch 'found
      (while (rpl-find-regexp search-direction rpl-indentation-modifier-regexp)
        ;; have we found a valid matching token?
        (let ((found-token (match-string 0))
              (found-pos (match-beginning 0)))
          (if (string-match match found-token)
              (throw 'found found-pos))
            ;; no - then there is a nested block. If we were looking for
            ;; a block begin token, found-token must be a block end
            ;; token; likewise, if we were looking for a block end token,
            ;; found-token must be a block begin token, otherwise there
            ;; is a grammatical error in the code.
            (if (not (and
                      (eq (car (cdr (cdr (assoc found-token rpl-block-token-alist))))
                          match-type)
                      (rpl-find-matching-token-word found-token nil)))
              (throw 'found nil)))))))

(defun rpl-goto-matching-block-token (&optional search-start parse-start)
  "Find block begion/end token matching the one at the point.
This function moves the point to the token that matches the one
at the current point. Returns the point position of the first character of
the matching token if successful, nil otherwise."
  (if parse-start (goto-char parse-start))
  (let ((case-fold-search nil))
    (if (looking-at rpl-indentation-modifier-regexp)
        (let ((position (rpl-find-matching-token-word (match-string 0)
                                                      search-start)))
          (and position
               (goto-char position))))))


;(defun rpl-goto-matching-block (&optional noreport)
;  "Go to the keyword balancing the one under the point.
;If the point is on a keyword/brace that starts a block, go to the
;matching keyword that ends the block, and vice versa."
;  (interactive)
;  ;; search backward to the beginning of the keyword if necessary
;  (if (eq (char-syntax (following-char)) ?w)
;      (re-search-backward "\\<" nil t))
;  (let ((position (rpl-goto-matching-block-token)))
;    (if (and (not position)
;             (not noreport))
;        (error "Not on a block control keyword or brace.")
;      position)))

(defun rpl-goto-nonblank-previous-line ()
  "Puts the point at the first previous line that is not blank.
Returns the point, or nil if it reached the beginning of the buffer"
  (catch 'found
    (beginning-of-line)
    (while t
      (if (bobp) (throw 'found nil))
      (forward-char -1)
      (beginning-of-line)
      (if (not (looking-at "\\s *\\(--.*\\)?$")) (throw 'found (point))))))

(defun rpl-goto-nonblank-next-line ()
  "Puts the point at the first next line that is not blank.
Returns the point, or nil if it reached the end of the buffer"
  (catch 'found
    (end-of-line)
    (while t
      (forward-line)
      (if (eobp) (throw 'found nil))
      (beginning-of-line)
      (if (not (looking-at "\\s *\\(--.*\\)?$")) (throw 'found (point))))))

(eval-when-compile
  (defconst rpl-operator-class
    "-+*/^.=<>~"))

(defconst rpl-cont-eol-regexp
  (eval-when-compile
    ;; expression used to generate the regexp
    (concat
     "\\("
;;     "\\<"
;;     (regexp-opt '("grammar" "enumerate" "transform") t)
;;     "\\>\\|"
     "\\(^\\|[^" rpl-operator-class "]\\)"
     (regexp-opt '("/" "=")  t)
     "\\)"
     "\\s *\\=")
    ))


(defconst rpl-cont-bol-regexp
  (eval-when-compile
    ;; expression used to generate the regexp
    (concat
     "\\=\\s *"
     "\\("
;     "\\<"
;     (regexp-opt '("and" "or" "not") t)
;     "\\>\\|"
     (regexp-opt '("." "*" "/" "^" "=" "<" ">" "(" ")" "[" "]" "!") t)
     "\\($\\|[^" rpl-operator-class "]\\)"
     "\\)"
     )
    ))

(defun rpl-last-token-continues-p ()
  "Returns true if the last token on this line is a continuation token."
  (let (line-begin
	line-end)
    (save-excursion
      (beginning-of-line)
      (setq line-begin (point))
      (end-of-line)
      (setq line-end (point))
      ;; we need to check whether the line ends in a comment and
      ;; skip that one.
      (while (rpl-find-regexp 'backward "-" line-begin 'rpl-string-p)
	(if (looking-at "--")
	    (setq line-end (point))))
      (goto-char line-end)
      (re-search-backward rpl-cont-eol-regexp line-begin t))))

(defun rpl-first-token-continues-p ()
  "Returns true if the first token on this line is a continuation token."
  (let (line-end)
    (save-excursion
      (end-of-line)
      (setq line-end (point))
      (beginning-of-line)
      (re-search-forward rpl-cont-bol-regexp line-end t))))

(defun rpl-is-continuing-statement-p (&optional parse-start)
  "Return nonnil if the line continues a statement.
More specifically, return the point in the line that is continued.
The criteria for a continuing statement are:

* the last token of the previous line is a continuing op,
  OR the first token of the current line is a continuing op

"
  (let ((prev-line nil))
    (save-excursion
      (if parse-start (goto-char parse-start))
      (save-excursion (setq prev-line (rpl-goto-nonblank-previous-line)))
      (and prev-line
	   (or (rpl-first-token-continues-p)
	       (and (goto-char prev-line)
		    ;; check last token of previous nonblank line
		    (rpl-last-token-continues-p)))))))


(defun rpl-make-indentation-info-pair ()
  "This is a helper function to rpl-calculate-indentation-info. Don't
use standalone."
  (cond ((string-equal found-token "grammar")
         ;; this is the location where we need to start searching for the
         ;; matching opening token, when we encounter the next closing token.
         ;; It is primarily an optimization to save some searchingt ime.
         (cons 'absolute (+ (save-excursion (goto-char found-pos)
                                            (current-column))
                            rpl-indent-level)))
        ((or ;(string-equal found-token "<")
	     (string-equal found-token "{")
	     (string-equal found-token "("))
         (save-excursion 
           ;; expression follows -> indent at start of next expression
           (if (and (not (search-forward-regexp "[[:space:]]--" (line-end-position) t))
                    (search-forward-regexp "[^[:space:]]" (line-end-position) t))
                 (cons 'absolute (1- (current-column)))
                 (cons 'relative rpl-indent-level))))
        ;; closing tokens follow
        ((string-equal found-token "end")
         (save-excursion
           (rpl-goto-matching-block-token nil found-pos)
           (if (looking-at "\\<grammar\\>")
               (cons 'absolute
                     (+ (current-indentation)
                        (rpl-calculate-indentation-block-modifier
                         nil (point))))
             (cons 'relative (- rpl-indent-level)))))
        ((or ;(string-equal found-token ">")
	     (string-equal found-token ")")
             (string-equal found-token "}"))
         (save-excursion
           (rpl-goto-matching-block-token nil found-pos)
           (cons 'absolute
                 (+ (current-indentation)
                    (rpl-calculate-indentation-block-modifier
                     nil (point))))))
        (t
         (cons 'relative (if (nth 2 (match-data))
                             ;; beginning of a block matched
                             rpl-indent-level
                           ;; end of a block matched
                           (- rpl-indent-level))))))



(defun rpl-calculate-indentation-info (&optional parse-start parse-end)
  "For each block token on the line, computes how it affects the indentation.
The effect of each token can be either a shift relative to the current
indentation level, or indentation to some absolute column. This information
is collected in a list of indentation info pairs, which denote absolute
and relative each, and the shift/column to indent to."
  (let* ((line-end (save-excursion (end-of-line) (point)))
         (search-stop (if parse-end (min parse-end line-end) line-end))
         (indentation-info nil))
    (if parse-start (goto-char parse-start))
    (save-excursion
      (beginning-of-line)
      (while (rpl-find-regexp 'forward rpl-indentation-modifier-regexp
                              search-stop)
        (let ((found-token (match-string 0))
              (found-pos (match-beginning 0))
              (found-end (match-end 0))
              (data (match-data)))
          (setq indentation-info
                (cons (rpl-make-indentation-info-pair) indentation-info)))))
    indentation-info))

(defun rpl-accumulate-indentation-info (info)
  "Accumulates the indentation information previously calculated by
rpl-calculate-indentation-info. Returns either the relative indentation
shift, or the absolute column to indent to."
  (let ((info-list (reverse info))
        (type 'relative)
        (accu 0))
    (mapcar (lambda (x)
            (setq accu (if (eq 'absolute (car x))
                           (progn (setq type 'absolute)
                                  (cdr x))
                         (+ accu (cdr x)))))
          info-list)
    (cons type accu)))

(defun rpl-calculate-indentation-block-modifier (&optional parse-start
                                                           parse-end)
  "Return amount by which this line modifies the indentation.
Beginnings of blocks add rpl-indent-level once each, and endings
of blocks subtract rpl-indent-level once each. This function is used
to determine how the indentation of the following line relates to this
one."
  (if parse-start (goto-char parse-start))
  (let ((case-fold-search nil)
        (indentation-info (rpl-accumulate-indentation-info
                           (rpl-calculate-indentation-info nil parse-end))))
    (if (eq (car indentation-info) 'absolute)
        (- (cdr indentation-info)
           (current-indentation)
           ;; reduce indentation if this line also starts new continued statement 
           ;; or next line cont. this line
           ;;This is for aesthetic reasons: the indentation should be
           ;;dosomething(d +
           ;;   e + f + g)
           ;;not
           ;;dosomething(d +
           ;;      e + f + g)"
           (save-excursion
             (or (and (rpl-last-token-continues-p) rpl-indent-level)
                 (and (rpl-goto-nonblank-next-line) (rpl-first-token-continues-p) rpl-indent-level)
                 0)))
      (+ (rpl-calculate-indentation-left-shift)
         (cdr indentation-info)
         (if (rpl-is-continuing-statement-p) (- rpl-indent-level) 0)))))


(defconst rpl-left-shift-regexp-1
  (concat "\\("
          "\\(\\<" ;;(regexp-opt '("else" "elseif" "until") t)
          "\\>\\)\\($\\|\\s +\\)"
          "\\)"))

(defconst rpl-left-shift-regexp-2
  (concat "\\(\\<"
          (regexp-opt '("end") t)
          "\\>\\)"))


(defconst rpl-left-shift-regexp
  ;; This is the code we used to generate the regexp:
  ;; ("else", "elseif", "until" followed by whitespace, or "end"/closing
  ;; brackets followed by
  ;; whitespace, punctuation, or closing parentheses)
  (concat ;;rpl-left-shift-regexp-1
          ;;"\\|"
	  "\\(\\("
          rpl-left-shift-regexp-2
          "\\|\\("
          (regexp-opt '("]" "}" ")"))
          "\\)\\)\\($\\|\\(\\s \\|\\s.\\)*\\)"
          "\\)"))

(defconst rpl-left-shift-pos-1
  2)

(defconst rpl-left-shift-pos-2
  (+ 3 (regexp-opt-depth rpl-left-shift-regexp-1)))

(defconst rpl-left-shift-pos-3
  (+ rpl-left-shift-pos-2
     (regexp-opt-depth rpl-left-shift-regexp-2)))


(defun rpl-calculate-indentation-left-shift (&optional parse-start)
  "Return amount, by which this line should be shifted left.
Look for an uninterrupted sequence of block-closing tokens that starts
at the beginning of the line. For each of these tokens, shift indentation
to the left by the amount specified in rpl-indent-level."
  (let (line-begin
        (indentation-modifier 0)
        (case-fold-search nil)
        (block-token nil))
    (save-excursion
      (if parse-start (goto-char parse-start))
      (beginning-of-line)
      (setq line-begin (point))
      ;; Look for the block-closing token sequence
      (skip-chars-forward rpl-indent-whitespace)
      (catch 'stop
        (while (and (looking-at rpl-left-shift-regexp)
                    (not (rpl-comment-or-string-p)))
          (let ((last-token (or (match-string rpl-left-shift-pos-1)
                                (match-string rpl-left-shift-pos-2)
                                (match-string rpl-left-shift-pos-3))))
            (if (not block-token) (setq block-token last-token))
            (if (not (string-equal block-token last-token)) (throw 'stop nil))
            (setq indentation-modifier (+ indentation-modifier
                                          rpl-indent-level))
                (forward-char (length (match-string 0))))))
      indentation-modifier)))

;; This was my version before rpl had grammar...end blocks.
;
;(defun rpl-calculate-indentation (&optional parse-start)
;  "Return appropriate indentation for current line as rpl code.
;In usual case returns an integer: the column to indent to."
;  (let ((pos (point)))
;    (save-excursion
;      (if parse-start (setq pos (goto-char parse-start)))
;      (beginning-of-line)
;      (cond ((bobp) (current-indentation)) ; If we're at the beginning of the buffer, no change.
;            ((rpl-is-continuing-statement-p) 
;             ;; Use the previous line's indent in case the user
;             ;; manually adjusted it.  Unless the previous line was
;             ;; the start of the statement
;             (goto-char pos)
;             (beginning-of-line)
;             (forward-line -1)
;             (if (rpl-is-continuing-statement-p)
;                 (current-indentation)  ; indent same as previous continuing line
;               rpl-indent-level))       ; indent this amt for first continuing line
;            (t 0))                      ; else no indent
;      )))

(defun rpl-calculate-indentation (&optional parse-start)
  "Return appropriate indentation for current line as rpl code.
In usual case returns an integer: the column to indent to."
  (let ((pos (point))
	shift-amt)
    (save-excursion
      (if parse-start (setq pos (goto-char parse-start)))
      (beginning-of-line)
      (setq shift-amt (if (rpl-is-continuing-statement-p) rpl-indent-level 0))
      (if (bobp)          ; If we're at the beginning of the buffer, no change.
	  (+ (current-indentation) shift-amt)
	;; This code here searches backwards for a "block beginning/end"
	;; It snarfs the indentation of that, plus whatever amount the
	;; line was shifted left by, because of block end tokens. It
	;; then adds the indentation modifier of that line to obtain the
	;; final level of indentation.
	;; Finally, if this line continues a statement from the
	;; previous line, add another level of indentation.
	(if (rpl-backwards-to-block-begin-or-end)
	    ;; now we're at the line with block beginning or end.
	    (max (+ (current-indentation)
		    (rpl-calculate-indentation-block-modifier)
		    shift-amt)
		 0)
	  ;; Failed to find a block begin/end.
	  ;; Just use the previous line's indent.
	  (goto-char pos)
	  (beginning-of-line)
	  (forward-line -1)
	  (+ (current-indentation) shift-amt))))))

;(defun rpl-beginning-of-proc (&optional arg)
;  "Move backward to the beginning of a rpl proc (or similar).
;With argument, do it that many times.  Negative arg -N
;means move forward to Nth following beginning of proc.
;Returns t unless search stops due to beginning or end of buffer."
;  (interactive "P")
;  (or arg
;      (setq arg 1))
;  (let ((found nil)
;                  (ret t))
;    (if (and (< arg 0)
;                                 (looking-at "^function[ \t]"))
;                  (forward-char 1))
;    (while (< arg 0)
;      (if (re-search-forward "^function[ \t]" nil t)
;                         (setq arg (1+ arg)
;                                         found t)
;                  (setq ret nil
;                                  arg 0)))
;    (if found
;                  (beginning-of-line))
;    (while (> arg 0)
;      (if (re-search-backward "^function[ \t]" nil t)
;                         (setq arg (1- arg))
;                  (setq ret nil
;                                  arg 0)))
;    ret))

;(defun rpl-end-of-proc (&optional arg)
;  "Move forward to next end of rpl proc (or similar).
;With argument, do it that many times.  Negative argument -N means move
;back to Nth preceding end of proc.
;
;This function just searches for a `end' at the beginning of a line."
;  (interactive "P")
;  (or arg
;      (setq arg 1))
;  (let ((found nil)
;        (ret t))
;    (if (and (< arg 0)
;             (not (bolp))
;             (save-excursion
;               (beginning-of-line)
;               (eq (following-char) ?})))
;        (forward-char -1))
;    (while (> arg 0)
;      (if (re-search-forward "^end" nil t)
;          (setq arg (1- arg)
;                found t)
;        (setq ret nil
;              arg 0)))
;    (while (< arg 0)
;      (if (re-search-backward "^end" nil t)
;          (setq arg (1+ arg)
;                found t)
;        (setq ret nil
;              arg 0)))
;    (if found
;        (end-of-line))
;    ret))

(defun rpl-start-process (name &optional program startfile &rest switches)
  "Start a rpl process named NAME, running PROGRAM."
  (or switches
      (setq switches rpl-default-command-switches))
  (setq program (or program name))
  (setq rpl-process-buffer (apply 'make-comint name program startfile switches))
  (setq rpl-process (get-buffer-process rpl-process-buffer))
  ;; wait for prompt
  (with-current-buffer rpl-process-buffer
    (while (not (rpl-prompt-line))
      (accept-process-output (get-buffer-process (current-buffer)))
      (goto-char (point-max)))
    (set-variable 'comint-process-echoes t) ; JAJ Monday, October 5, 2015
    ))

(defun rpl-kill-process ()
  "Kill rpl subprocess and its buffer."
  (interactive)
  (if rpl-process-buffer
      (kill-buffer rpl-process-buffer)))

(defun rpl-set-rpl-region-start (&optional arg)
  "Set start of region for use with `rpl-send-rpl-region'."
  (interactive)
  (set-marker rpl-region-start (or arg (point))))

(defun rpl-set-rpl-region-end (&optional arg)
  "Set end of region for use with `rpl-send-rpl-region'."
  (interactive)
  (set-marker rpl-region-end (or arg (point))))

(defun rpl-send-current-line ()
  "Send current line to rpl subprocess, found in `rpl-process'.
If `rpl-process' is nil or dead, start a new process first."
  (interactive)
  (let ((start (save-excursion (beginning-of-line) (point)))
        (end (save-excursion (end-of-line) (point))))
    (rpl-send-region start end)))

(defun rpl-send-region (start end)
  "Send region to rpl subprocess."
  (interactive "r")
  ;; make temporary rpl file
  (let ((tempfile (rpl-make-temp-file "rpl-"))
	(last-prompt nil)
	(prompt-found nil)
	(rpl-stdin-line-offset (count-lines (point-min) start))
	(rpl-stdin-buffer (current-buffer))
	current-prompt )
    (write-region start end tempfile)
    (or (and rpl-process
	     (comint-check-proc rpl-process-buffer))
	(rpl-start-process rpl-default-application))
    ;; kill rpl process without query
    (if (fboundp 'process-kill-without-query) 
	(process-kill-without-query rpl-process)) 
    ;; send dofile(tempfile)
    (with-current-buffer rpl-process-buffer   
      (goto-char (point-max))
      (setq last-prompt (point-max))
      (comint-simple-send (get-buffer-process (current-buffer)) 
			  (format "dofile(\"%s\")"  
				  (replace-in-string tempfile "\\\\" "\\\\\\\\" )))
      ;; wait for prompt
      (while (not prompt-found) 
	(accept-process-output (get-buffer-process (current-buffer)))
	(goto-char (point-max))
	(setq prompt-found (and (rpl-prompt-line) (< last-prompt (point-max)))))
    ;; remove temp. rpl file
    (delete-file tempfile)
    (rpl-postprocess-output-buffer rpl-process-buffer last-prompt rpl-stdin-line-offset)    
    (if rpl-always-show
	(display-buffer rpl-process-buffer)))))

(defun rpl-prompt-line ()
  (save-excursion 
    (save-match-data
      (forward-line 0)
      (if (looking-at comint-prompt-regexp)
	  (match-end 0)))))

(defun rpl-send-rpl-region ()
  "Send preset rpl region to rpl subprocess."
  (interactive)
  (or (and rpl-region-start rpl-region-end)
      (error "rpl-region not set"))
  (or (and rpl-process
           (comint-check-proc rpl-process-buffer))
      (rpl-start-process rpl-default-application))
  (comint-simple-send rpl-process
                              (buffer-substring rpl-region-start rpl-region-end)
)
  (if rpl-always-show
      (display-buffer rpl-process-buffer)))

(defun rpl-send-buffer ()
  "Send whole buffer to rpl subprocess."
  (interactive)
  (rpl-send-region (point-min) (point-max)))

(defun rpl-restart-with-whole-file ()
  "Restart rpl subprocess and send whole file as input."
  (interactive)
  (rpl-kill-process)
  (rpl-start-process rpl-default-application)
  (rpl-send-buffer))

(defun rpl-show-process-buffer ()
  "Make sure `rpl-process-buffer' is being displayed."
  (interactive)
  (display-buffer rpl-process-buffer))

(defun rpl-hide-process-buffer ()
  "Delete all windows that display `rpl-process-buffer'."
  (interactive)
  (delete-windows-on rpl-process-buffer))

(defun rpl-calculate-state (arg prevstate)
  ;; Calculate the new state of PREVSTATE, t or nil, based on arg. If
  ;; arg is nil or zero, toggle the state. If arg is negative, turn
  ;; the state off, and if arg is positive, turn the state on
  (if (or (not arg)
	  (zerop (setq arg (prefix-numeric-value arg))))
      (not prevstate)
    (> arg 0)))

(defun rpl-toggle-electric-state (&optional arg)
  "Toggle the electric indentation feature.
Optional numeric ARG, if supplied, turns on electric indentation when
positive, turns it off when negative, and just toggles it when zero or
left out."
  (interactive "P")
  (setq rpl-electric-flag (rpl-calculate-state arg rpl-electric-flag)))

; (define-key rpl-mode-menu [restart-with-whole-file]
;   '("Restart With Whole File" .  rpl-restart-with-whole-file))
; (define-key rpl-mode-menu [kill-process]
;   '("Kill Process" . rpl-kill-process))
;
; (define-key rpl-mode-menu [hide-process-buffer]
;   '("Hide Process Buffer" . rpl-hide-process-buffer))
; (define-key rpl-mode-menu [show-process-buffer]
;   '("Show Process Buffer" . rpl-show-process-buffer))
;
; (define-key rpl-mode-menu [end-of-proc]
;   '("End Of Proc" . rpl-end-of-proc))
; (define-key rpl-mode-menu [beginning-of-proc]
;   '("Beginning Of Proc" . rpl-beginning-of-proc))
;
; (define-key rpl-mode-menu [send-rpl-region]
;   '("Send rpl-Region" . rpl-send-rpl-region))
; (define-key rpl-mode-menu [set-rpl-region-end]
;   '("Set rpl-Region End" . rpl-set-rpl-region-end))
; (define-key rpl-mode-menu [set-rpl-region-start]
;   '("Set rpl-Region Start" . rpl-set-rpl-region-start))
;
; (define-key rpl-mode-menu [send-current-line]
;   '("Send Current Line" . rpl-send-current-line))
; (define-key rpl-mode-menu [send-region]
;   '("Send Region" . rpl-send-region))
; (define-key rpl-mode-menu [send-proc]
;   '("Send Proc" . rpl-send-proc))
; (define-key rpl-mode-menu [send-buffer]
;   '("Send Buffer" . rpl-send-buffer))


(provide 'rpl-mode)


