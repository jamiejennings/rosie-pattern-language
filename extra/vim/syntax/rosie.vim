" Vim syntax file
" Language:     Rosie Pattern Language
" Maintainer:   Kevin Zander <veratil@gmail.com>
" Contributors:
" Last Change:  07-Dec-2016
" Bugs:

if version < 600
	syntax clear
elseif exists("b:current_syntax")
	finish
endif

" for future expansion, not used now
function! s:GetRPLVersion()
	if exists("b:rosie_version")
		return b:rosie_version
	elseif exists("g:rosie_version")
		return g:rosie_version
	else
		return 999
	endif
endfunction

" alias name = expression
syn	keyword	rosieKeyword	alias

" grammar
"  ...
" end
syn	keyword	rosieGrammar	grammar end

" { ... }
syn	match	rosieRawGroup	"{"
syn	match	rosieRawGroup	"}"

" ( ... )
syn	match	rosieCookedGroup	"("
syn	match	rosieCookedGroup	")"

syn	match	rosieAssignment	"="

syn	match	rosieChoice	"/"

syn	match	rosieRepetition	"*"
syn	match	rosieRepetition	"?"
syn	match	rosieRepetition	"+"

" Repetition specific
syn	match	rosieRepetitionRange	/{\s*\d*\s*,\s*\d*\s*}/

syn	match	rosiePredicate	"!"
syn	match	rosiePredicate	"@"

syn	match	rosieCharlist		/\v\[\^?[^[\]]+]/
syn	match	rosieRange			/\v\[\^?([^\\[^\]]|\\.)-([^\\[^\]]|\\.)]/
syn	match	rosieNamedCharset	/\v\[:\^?[^:]+:]/

" This looks for two open square brackets, skipping whitespace
" The region contains any of the above sets (highlighted separately)
" The end will match the final ] as the inside matches will consume their ]
syn	region	rosieCharset	start=/\v\[\[/	end=/\v]/	skipwhite contains=rosieCharlist,rosieRange,rosieNamedCharset oneline

syn	region	rosieString		start=+"+	skip=+\\\\\|\\"+	end=+"+	oneline

syn	region	rosieComment	start="--"	end="$" oneline

highlight	link	rosieKeyword			Keyword
highlight	link	rosieGrammar			Typedef
highlight	link	rosieString				String
highlight	link	rosieComment			Comment
highlight	link	rosieAssignment			Operator
highlight	link	rosieChoice				Operator
highlight	link	rosieRepetition			Operator
highlight	link	rosieRepetitionRange	Define
highlight	link	rosieRawGroup			Structure
highlight	link	rosieCookedGroup		StorageClass
highlight	link	rosiePredicate			Delimiter
highlight	link	rosieCharset			Macro
highlight	link	rosieCharlist			Label
highlight	link	rosieRange				Delimiter
highlight	link	rosieNamedCharset		Include

let b:current_syntax = "rosie"

" vim:ts=4
