<!--  -*- Mode: GFM; -*-                                                     -->
<!--                                                                         -->
<!--  posix.md                                                               -->
<!--                                                                         -->
<!--  © Copyright IBM Corporation 2016.                                      -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  -->
<!--  AUTHOR: Jamie A. Jennings                                              -->



The POSIX standard defines 12 character classes.  The POSIX standard does not define a Unicode locale. 

 POSIX	    | Description	                                        | ASCII equiv.                            | Unicode
 ---------- | ----------------------------------------------------- | --------------------------------------- | -------------------
`[:alnum:]`	| Alphanumeric characters                               | `[a-zA-Z0-9]`	                              | `[\p{L}\p{Nl}\p{Nd}]`
`[:alpha:]`	| Alphabetic characters	                                | `[a-zA-Z]`	                              | `\p{L}\p{Nl}`
`[:blank:]`	| Space and tab                                         | `[ \t]`	                                  | `[\p{Zs}\t]`
`[:cntrl:]`	| Control characters	                                | `[\x00-\x1F\x7F]`                           | `\p{Cc}`
`[:digit:]`	| Digits	                                            | `[0-9]`                                     | `\p{Nd}`
`[:graph:]`	| Visible characters (no spaces or control characters)  | `[\x21-\x7E]`                               | `[^\p{Z}\p{C}]`
`[:lower:]`	| Lowercase letters	                                    | `[a-z]`                                     | `\p{Ll}`
`[:print:]`	| Visible characters and spaces (no control characters) | `[\x20-\x7E]`                               | `\P{C}`
`[:punct:]`	| Punctuation	                                        | `[!"\#$%&'()*+,\-./:;<=>?@\[\\\]^_``{|}~]`  | `\p{P}`
`[:space:]`	| Whitespace characters (including line breaks)         | `[ \t\r\n\v\f]`                             | `[\p{Z}\t\r\n\v\f]`
`[:upper:]`	| Uppercase letters	                                    | `[A-Z]`                                     | `\p{Lu}`
`[:xdigit:]`| Hexadecimal digits                                    | `[A-Fa-f0-9]`                               | `[A-Fa-f0-9]`



