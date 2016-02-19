<!--  -*- Mode: GFM; -*-  -->
<!--
  -- (c) 2015, Jamie A. Jennings
  --
-->


# Rosie Pattern Language v0.88

## How to install new patterns

The only patterns that are truly built-in are `.` (dot) and `$` (dollar sign), which match any character and the end of line, respectively.  Therefore, you'll probably want to build your patterns by starting with some of the ones in the Rosie rpl directory.

Rpl files contain Rosie Pattern Language, which Rosie compiles.  When Rosie starts, a list of rpl files is compiled and loaded.  That list is in the file [MANIFEST](../MANIFEST) in the install directory by default.  The command line switch `-manifest <filename>` lets you specify a different manifest file, which is simply a list of `.rpl` files to load.

Usually, the default manifest loads these rpl files: (your distribution may differ)

| File              |  Contents |
| ----------------- | --------- |
| rpl/common.rpl    | commonly used patterns for numbers, words, identifiers, pathnames |
| rpl/datetime.rpl  | dates and times in a variety of formats |
| rpl/network.rpl	| ip address, hostname, http commands, email addresses |
| rpl/syslog.rpl	| patterns for the kind of syslog entries produced by Service Exchange |
| rpl/basic.rpl		| patterns for finding a variety of "basic" patterns of semantic interest in arbitrary input |

A good first experiment when using Rosie is to match the pattern `basic.matchall` against an arbitrary input file.


## RPL reference

### Statements

RPL patterns can contain whitespace and comments, so you can make your patterns easy to read.  The RPL statements supported in this version of Rosie are:

|  RPL statement | Meaning                       |
|  -------------- | -------                      |
|  `identifier = expression`         | Assign a name to a pattern expression |
|  `alias identifier = expression`  | Create an alias for a pattern expression |
|  `grammar ... end`                | Define a proper grammar; assignments and aliases appear in place of `...` |

When Rosie matches an identifier, say `int`, the entire matched string is
returned, along with an ordered list of sub-matches.  Each sub-match corresponds
to an identifier used to define `int`, such as `d` (for digit).

When you don't care about sub-matches, define an `alias` instead.  For example:

```
d = [:digit:]
common.int = { [+-]? d+ }
``` 

When `common.int` is matched against input "421", Rosie will output:

```
{"common.int":{"1":{"d":{"pos":1,"text":"4"}},"2":{"d":{"pos":2,"text":"2"}},"3":{"d":{"pos":3,"text":"1"}},"pos":1,"text":"421"}}
```

This is the default behavior because Rosie assumes that if you gave a pattern
(like `[:digit:]`) a name (like `d`), then you must care a lot about this thing
called `d` and you want to see all of its components.  When that is not the case, use `alias`.

So, in this example, unless you care about the individual digits, you should
define `d` as an alias:

``` 
alias d = [:digit:]
common.int = { [+-]? d+ }
``` 

Matching against "421" now gives:

``` 
{"common.int":{"pos":1,"text":"421"}}
``` 

### Grammars are an advanced feature you may never need

Grammars can have mutually recursive rules.  PEGs allow you to define grammars for recursive structures like nested lists (e.g. JSON, XML) or things like "strings that have an equal number of a's and b's".  Here is an interactive Rosie session in which a grammar called `same` has been defined to match strings that have equal a's and b's:

	``` 
	Rosie> same
	same = grammar
	   assignment same = S $
	   alias S = ({"a" B} / ({"b" A} / ""))
	   alias A = ({"a" S} / {"b" A A})
	   alias B = ({"b" S} / {"a" B B})
	end
	Rosie> .match same, "aabaabbb"
	[same: 
	 [pos: 1, 
	  text: "aabaabbb"]]
	Rosie> .match same, "aab"
	  1..GRAMMAR:
		 grammar
			assignment same = S $
			alias S = ({"a" B} / ({"b" A} / ""))
			alias A = ({"a" S} / {"b" A A})
			alias B = ({"b" S} / {"a" B B})
		 end
		 FAILED to match against input "aab"
	Repl: No match (turn debug off to hide the match trace)
	Rosie>
    ``` 

**IMPORTANT NOTE:** Debugging grammars using the `-debug` command line option is not currently supported.  Even worse, the syntax error reporting for grammars is atrocious.  This is on the TO DO list.


### Expressions

Here are some key things to remember:

* To match a literal string, enclose it in double quotes.  Outside of quotes you can use identifiers to which you have already assigned patterns, aliases, or grammars.
* Normally, Rosie looks for word boundaries automatically.  A word boundary can be whitespace (which is consumed and discarded) or punctuation.  To proceed character by character instead, put curly braces `{...}` around your expression, which puts Rosie in "raw mode".
* Choices are made with the slash `\` operator, not a vertical bar, because PEGs use an _ordered choice_.  See [below](#regex_vs_rpl) for more.

Rosie's pattern expressions are as follows (note the similarity to regexes):

|  RPL expression | Meaning                      |
|  -------------- | -------                      |
|  `"abcdef"`     | (String literal) Matches the string `abcdef`.  E.g. `"Hello, world"` matches only the input "Hello, world", with exactly one space after the comma |
|  `pat?`         | Zero or one instances of `pat`                      |
|  `pat*`         | Zero or more instances of `pat`                      |
|  `pat+`         | One or more instances of `pat`                      |
|  `pat?`         | Zero or one instances of `pat`                      |
|  `pat{n,m}`         | Bounded repetition of `pat`.  Each of `n` and `m` are optional. |
|  `!pat`         | Not looking at `pat` (predicate: consumes no input)                      |
|  `@pat`         | Looking at `pat` (predicate: consumes no input)                       |
|  `p / q`        | Ordered choice between `p` and `q`     |
|  `p q`          | Sequence of `p` followed by `q`     |
|  `(...)`         | _Cooked group_, the default mode, in which Rosie divides the input into tokens automatically |
|  `{...}`         | _Raw group_, which tells Rosie to process character by character |
|  `[:name:]`      | Named character classes are from the POSIX standard:  alpha, xdigit, digit, print, cntrl, lower, space, alnum, upper, punct, graph  |
|  `[x-y]`         | Range character class, from character x to character y  |
|  `[...]`      | List character class, which matches any of the characters listed (in place of `...`) |


**NOTES:**
1. The "quantified expressions" `pat?`, `pat*`, `pat+`, and `pat?` are _greedy_.  They will consume as many repetitions as possible, always.
2. The two grouping constructs (raw and cooked) are used in the way that parentheses are usually used in programming: to force the order of operations that you want.  So if you want "a or b, followed by c", write `(a / b) c` or `{ {a / b} c }`.
3. Inside of quotation marks, the only special character is `\` (backslash), which is the escape character.  Inside of a character set (in square brackets `[]`), the only special character is `-`, which is only special when it is the middle of three characters, specifying a character range.

### Matches/Captures

The real output of Rosie is structured in a way that mirrors the pattern that was matched.  You can see the structure if you look at the JSON output from Rosie.  (On a terminal, the default is for Rosie to print the matched pieces of input in color.  Use the `-json` flag to get JSON instead.)  There will be one JSON structure for each line in the input, and each structure is called a *match*.  A match contains the name of the pattern that generated it, the starting position in the input of the matched text, the matched text itself, and any *sub-matches*.  Sub-matches have the same structure as matches.

A match output by Rosie is kind of like a capture in regex.  Except way cooler, because a match has the recursive structure of a parse tree. (In the language of compilers, Rosie's output is an *abstract syntax tree*.)

There are a few really important things you need to know about Rosie's matches:

1. Sub-matches are captured only for the identifiers in a pattern.  And only when those identifiers are *not* aliases.  Sub-matches are indexed by the identifier name that generated them.
2. Literal strings in patterns are not returned as sub-matches.  This is a special case of the previous rule.  
3. If you *want* a literal string or some other expression (e.g. `[:digit:]{3,3}`) to appear as a sub-match, assign it a name.  Here's an example where a literal string is assigned the name `down_message`.  The pattern `alert` contains the identifier `down_message`, and so there will be a sub-match of `alert` called `down_message`:

```
down_message = "The system will go down in"
delay = common.int "seconds"

alert = down_message delay
```

4. Aliases are like macros, i.e. substitutions.  They do not create a new named capture like ordinary (non-alias) named patterns do.  (Rationale:  Aliases let you give names to patterns, so that you can refer to them by name, without declaring that you want this name to appear as a separate capture/match in Rosie's output.)  The choice between assigning a name to a pattern and creating an alias for the same pattern gives you some control over what appears in the output.




## If you know regex already, this is RPL <a name="regex_vs_rpl"></a>

### Anchors

* A Rosie pattern begins matching at the start of the input line, so there is no `^` (caret) anchor in RPL.  To skip over characters, you have to be explicit in your pattern about what to skip.  See [below](#find_patterns) for more.
* A Rosie pattern will match successfully even if the entire input is not consumed.  To force a match of the complete input line, use the `$` anchor at the end of your pattern to mark the end of the input line.
* Rosie automatically tokenizes the input in a way similar to the "word boundary" (\b) anchor in regex, so there is no word boundary anchor in Rosie.  (You could, of course, write one.)

### Ordered choice

The "alternation" operator in a Rosie pattern is an _ordered choice_.  Instead of using the pipe symbol `|`, which represents equal alternatives in regex, Rosie uses a forward slash `/` to denote an ordered choice between two alternatives.  The pattern `(a / b) c` is read as "a or b, followed by c" and is processed this way:

1. If `a` matches the start of the input, then the choice is satisfied, so go on to match `c`
2. Else if `b` matches the start of the input, then the choice is satisfied, so go on to match `c`
3. Otherwise, the entire pattern fails because `(a / b)` could not be matched

Once a choice is made, Rosie will never backtrack and try another alternative.  Let's make that clear with a different example.  The PEG pattern `a / (a b)` will not match the input "a b" because the pattern will never look for b.  This pattern is processed as follows:

1. If `a` matches the start of the input, then the ordered choice is satisfied, and the overall pattern succeeds
2. Else try the next alternative, `(a b)`.  The sequence `(a b)` will always fail because we arrived here due to the fact that we could not match `a`.  If we cannot match `a`, then we cannot match the sequence `(a b)`.

The order of the alternatives matters in PEG.  The pattern `(a b) / a` will match input "a b", because this pattern looks for the sequence "a b" first.

When writing PEG patterns, then, we must pay attention to the order of choices in an alternation expression.  Ordered choices are part of Parse Expression Grammars, and while they place constraints on pattern writers, they help guarantee linear-time execution.

### "Cooked" or "tokenized" mode

Normally, Rosie tokenizes the input, using whitespace and punctuation to separate the tokens.  Most of the time, this just _does the right thing_, such as when you're trying to match a noun followed by a verb, or a timestamp followed by an ip address.  As a trivial example, consider:

```
a = "a"
b = "b"
``` 

The expression `a b` will match the input "a b" (and "a \t \n  b", etc.) and produce this output:

``` 
[*: 
 [1: [a: 
       [pos: 1, 
        text: "a"]], 
  2: [b: 
       [pos: 3, 
        text: "b"]], 
  pos: 1, 
  text: "a b"]]
``` 

But `a b` will **not** match the input "ab".  Neither will `(a b)`, because parentheses group together "cooked" expressions.  An expression like `a b` or `(a b)` should be read as "a, then a token boundary, then b".   The definition of a token boundary includes all of the following conditions:

	* looking at punctuation, or
	* consuming whitespace, or
	* looking back at punctuation but ahead at non-punctuation, or
	* looking behind at whitespace but ahead at non-whitespace, or
	* at the end of the input"

If you wanted to match "ab", then you do not want to match `a` and `b` as separate tokens, but instead as raw characters.  You need the raw mode expression `{a b}` to match "ab", which will produce this output:

``` 
[*: 
 [1: [a: 
       [pos: 1, 
        text: "a"]], 
  2: [b: 
       [pos: 2, 
        text: "b"]], 
  pos: 1, 
  text: "ab"]]
``` 

**NOTE:** The name of the matched pattern is "*" in the examples above because the pattern `a b` was entered on the command line.  If we had defined `foo = a b` and then matched against `foo`, the output would have been `{"foo":{"1":{"a":{"pos":1,"text":"a"}},"2":{"b":{"pos":3,"text":"b"}},"pos":1,"text":"a b"}}` instead.

When you quantify a simple expression using `*`, `+`, `?`, or `{n,m}`, Rosie will treat the expression as if it were raw.  So `"foo"+` will match "foofoofoo" and not "foo foo foo".  You can force a tokenized match using a cooked group: `("foo")+` will match "foo foo foo".  Most of the time, quantified expressions are used in character-oriented syntactic patterns, so the default usually _does the right thing_.

But for that occasion when you want to match exactly two ip addresses separated by whitespace, be sure to write `(network.ip_address){2,2}`.

### Greedy quantifiers

There is one way in which regex are particularly concise, which is when you want to match a pattern that _ends_ in a recognizable way.  For example, words from `/usr/dict/words` that end in "ear" can be found with the expression `.*ear$` as an argument to `grep`:

```sh
jjennings$ grep -x .*ear$ /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
```

In fact, grep assumes the `.*` at the start of the pattern and lets you write just `grep 'ear$' /usr/share/dict/words | head -5`, because grep returns the entire line, not just the part that matches the pattern.  Rosie behaves like `grep -x`, where the `-x` option makes grep return just the part of the line that matches the pattern.  When using Rosie (or `grep -x`), the `.*` is an important part of the pattern, because without it we will get only the word "ear" out of the 235,000 or so words in `/usr/dict/words`.

<a name="find_patterns"></a>
In PEG patterns, quantifiers like `*` are greedy and will eat up as much input as possible.  The pattern `.*ear` will never match anything in a PEG grammar, because the `.*` will consume all the input, leaving nothing to match "ear".  You have to tell a PEG pattern when to _stop_ consuming input.  (This is one reason that PEG grammars are efficient.)

To write a PEG pattern that consumes characters (`.`) up until the string "ear" is seen, write:

``` 
{ !"ear" . }*
```

The part of the pattern inside the braces is read as "while not looking at _ear_, match any character".  The star `*` says to repeat this zero or more times.

But this is not quite enough, because this pattern will consume characters as long as it does not see "ear", so words that do not contain "ear" at all will match!  We want to make sure our match includes "ear", and includes it at the end of the line.  So we write this:

```json 
{{!"ear" .}* "ear"}$
``` 

The pattern above says "while not looking at _ear_, consume all characters; then match _ear_ at the end of the line."  Using this expression, we get:

```shell 
bash-3.2$ ./run '{{!"ear" .}* "ear"}$' /usr/share/dict/words | head -5
abear 
afear 
anear 
appear 
arear 
``` 

Observe that the form of this pattern is `{{ !X .}* X}`, in other words, "consume all input up to and including `X`, then stop.  There may be other elements after this expression, such as the end of line expression, `$`, or before the expression as in this example which finds words that start with "c" and end with "ear":


```shell 
bash-3.2$ ./run '{"c" {!"ear" .}* "ear"$}' /usr/share/dict/words
circumnuclear 
clear 
coappear 
cochlear 
coendear 
colinear 
collinear 
compear 
countershear 
cudbear 
curvilinear 
``` 

The expression `{ !X .}* X` may be needed sufficiently often as to warrant an addition to the Rosie Pattern Language to express it.  The `alias` capability in Rosie is intended to evolve into the kind of macro facility that would _in the future_ allow a user to write:

```lua
-- This does not work today!  Currently, an alias cannot take an argument.
alias match_until(X) = { { !X .}* X }
```

**Notes on the examples in this section:**
1. Sending the standard error output to /dev/null using `2>/dev/null` hides all the Rosie messages, such as which pattern files are being compiled, and which input lines do not match the supplied pattern.  Such messages are typically printed only when using the `-verbose` command line option.
2. The pattern entered on the command line is in single quotes so that the shell does not interpret any of the pattern characters.
3. On MacOSX, /usr/dict/words is located at /usr/share/dict/words.

### Matching the entire input line with nothing left over

Rosie is happy to match the first part of a line and ignore the rest.  Often, this is a good thing, but not always.  If you want to be sure that the entire input matches your pattern with no input left over, use the "end of input" pattern, `$`.

The expression `{a b}` will match the input "abcdef" and return:

``` 
{"*":[1,"ab",{"a":[1,"a"]},{"b":[2,"b"]}]}
``` 

While the expression `{a b}$` will not match "abcdef".

### Matching starting at the first character of the line

Currently, the Rosie Pattern Engine begins matching with the first character of the input.  Therefore, if you want to start matching after initial whitespace, you must explicitly specify that, e.g.


``` 
Rosie> .match common.number, "   123"
Repl: No match (turn debug on to show the match trace)
Rosie> .match [:space:]* common.number, "   123"
[*: 
 [pos: 1, 
  subs: 
   [1: [common.number: 
         [pos: 4, 
          subs: 
           [1: [common.hex: 
                 [pos: 4, 
                  subs: 
                   [], 
                  text: "123"]]], 
          text: "123"]]], 
  text: "   123"]]
Rosie> 
```

**Note: The default behavior in this case may change with Rosie Pattern Engine v1.0.**

