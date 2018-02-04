<!--  -*- Mode: GFM; -*-                                                       -->
<!--                                                                           -->
<!--  © Copyright IBM Corporation 2016, 2017, 2018                             -->
<!--  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  -->
<!--  AUTHOR: Jamie A. Jennings                                                -->

## If you know regex, this is RPL <a name="regex-vs-rpl"></a> 

### Anchors, tokens, and matching only part of the input

* A Rosie pattern begins matching at the start of the input line, so the `^` (caret) anchor is rarely needed in RPL.  To skip over characters, you have to be explicit in your pattern about what to skip.  See [below](#find_patterns) for more.
* A Rosie pattern will match successfully even if the entire input is not consumed.  To force a match of the complete input line, use the `$` anchor at the end of your pattern to force a match to the end of the input.
* Rosie automatically tokenizes the input in a way similar to the "word boundary" (`\b`) anchor in regex.  There is a Rosie identifier `~` that refers to the boundary definition used by Rosie.  You can use it explictly as needed, e.g. `~date.any~` matches the pattern `date.any` (from [rpl/date.rpl](../rpl/date.rpl)) only when there is a token boundary before and after it.

### Ordered choice

The "alternation" operator in a Rosie pattern is an _ordered choice_.  Instead of using the pipe symbol `|`, which represents equal alternatives in regex, Rosie uses a forward slash `/` to denote an ordered choice between two alternatives.  The pattern `(a / b) c` is read as "a or b, followed by c" and is processed this way:

1. If `a` matches the start of the input, then the choice is satisfied, so go on to match `c`
2. Else if `b` matches the start of the input, then the choice is satisfied, so go on to match `c`
3. Otherwise, the entire pattern fails because `(a / b)` could not be matched

Once a choice is made, Rosie will never backtrack and try another alternative:
Rosie matches are _possessive_.  Let's make that clear with a different example.
The RPL pattern `a / (a b)` will not match the input "a b" because the pattern
will never look for b.  This pattern is processed as follows:

1. If `a` matches the start of the input, then the choice is satisfied, and the overall pattern succeeds
2. Else try the next alternative, `(a b)`.  The sequence `(a b)` will always fail because we arrived here due to the fact that we could not match `a`.  If we cannot match `a`, then we cannot match the sequence `(a b)`.

The order of the alternatives matters in Rosie.  The pattern `(a b) / a` will match input "a b", because this pattern looks for the sequence "a b" first.

When writing RPL patterns, then, we must pay attention to the order of choices
in an alternation expression.  Ordered choices are part of Parsing Expression
Grammars, on which RPL is based.  While ordered choices place some constraints
on pattern writers (to put the alternatives in a suitable order), they help the
matching process avoid backtracking.

### Tokenized expressions

Normally, Rosie tokenizes the input, using whitespace and punctuation to separate the tokens.  Most of the time, this just _does the right thing_, such as when you're trying to match a noun followed by a verb, or a timestamp followed by an ip address.  As a trivial example, consider:

```
a = "a"
b = "b"
``` 

The expression `a b` will match the input "a b" (and "a \t \n  b", etc.) and produce this output:

``` 
$ rosie repl
Rosie> a="a"; b="b"
Rosie> .match a b "a b"
{"data": "a b", 
 "e": 4, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 4, 
     "s": 3, 
     "type": "b"}], 
 "type": "*"}
Rosie> .match a b "a     b"
{"data": "a     b", 
 "e": 8, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 8, 
     "s": 7, 
     "type": "b"}], 
 "type": "*"}
Rosie> 
``` 

But the pattern `a b` will **not** match the input "ab", because a token boundary
must be found between "a" and "b".  We can verify that the pattern `a b` is
interpreted as having a token boundary by using Rosie's `expand` command:

```
$ rosie expand 'a b'
Expression:     a b
Parses as:      a b
At top level:   (a b)
Expands to:     {a ~ b}
$ 
``` 

In the example above:
* `Expression: a b` echoes the expression, so you can observe any shell expansions.
* `Parses as: a b` shows the result of applying the RPL parser to the expression.
* `At top level: (a b)` means that the "bare" sequence of `a` and then `b` is
  interpeted as a tokenized expression, which would be written explicitly as `(a b)`.
* `Expands to: {a ~ b}` shows the syntax expansion of a tokenized expression
  into an untokenized expression with explicit boundary patterns (`~`).

An bare expression like `a b` or an explicitly tokenized expression like `(a b)` should be read as "a, then a token boundary, then b".   

If you wanted to match "ab", then you do not want to match `a` and `b` as
separate tokens, but instead as individual characters.  You want an untokenized
(or "raw") sequence `{a b}` to match "ab":

``` 
Rosie> .match {a b} "a b"
No match  [Turn debug on to show the trace output]
Rosie> .match {a b} "ab"
{"data": "ab", 
 "e": 3, 
 "s": 1, 
 "subs": 
   [{"data": "a", 
     "e": 2, 
     "s": 1, 
     "type": "a"}, 
    {"data": "b", 
     "e": 3, 
     "s": 2, 
     "type": "b"}], 
 "type": "*"}
Rosie> 
``` 

**NOTE:** The name of the matched pattern is "*" in the examples above because the pattern `a b` was entered on the command line.  I.e. it does not have a name.

### Repetitions and tokenization

Recall that a _bare_ expression is one that is not explicitly tokenized (with
parentheses) or untokenized (with curly braces).  The bareness of an expression
matters when the expression is a sequence, like `a b`, and when the expression
is being repeated, like `a*`.

When you modify a bare expression using `*`, `+`, `?`, or `{n,m}`, Rosie will
treat the expression as if it were untokenized.  So `"foo"+` will match "foofoofoo" and
not "foo foo foo".  

To repeat an expression with token boundaries between each instance, use
parentheses around the expression to make it explicitly tokenized:
`("foo")+` will match "foo foo foo".  Most of the time, quantified expressions
are used in character-oriented syntactic patterns, so the default usually _does
the right thing_.

But for that occasion when you want to match exactly two ip addresses separated
by whitespace, be sure to write `(net.ip){2}`.  The way to read this expression
is to remember that the repetition operator (`{2}` in this example) causes Rosie
to look for a sequence in which the expression (`net.ip` here) is repeated.  

Since the pattern `(net.ip)` is inside parentheses, the sequence `(net.ip){2}`
is equivalent to `(net.ip net.ip)`, which in turn expands into `{net.ip ~
net.ip}`.


### RPL is greedy

One way in which regex are particularly concise is when you want to match a
pattern that _ends_ in a recognizable way.  For example, words from
`/usr/share/dict/words` that end in "ear" can be found with the regular expression
`.*ear$` as an argument to `grep`:

```sh
$ grep .*ear$ /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
```

<a name="find_patterns"></a> In RPL patterns, repetitions like `*` are greedy
and will eat up as much input as possible.  The RPL pattern `.*ear` will never
match anything, because the `.*` will consume all the input, leaving nothing to
match "ear".  You have to tell Rosie when to _stop_ consuming input.  (This is
one reason that RPL grammars are efficient.)

To write an RPL pattern that consumes characters until the string "ear" is found, and then match "ear", you could write:

```
{ !"ear" . }* "ear"
```

The part of the pattern inside the braces reads as "while not looking at _ear_, match any character".  The star `*` says to repeat this zero or more times.

Because this is a frequent idiom, Rosie provides a macro called `find` that
searches for a pattern, and then consumes it.  For example, let's look for words
that end in "ear" in the dictionary present on most Unix systems:

``` 
$ rosie match -o line '{ {!"ear" .}* "ear" $}' /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
$ rosie match -o line '{ find:"ear" $}' /usr/share/dict/words | head -5
abear
afear
anear
appear
arear
$ 
```

Another common use of Unix grep is to find all occurrences of a pattern.  (The
`grep -o` option will print all of the matches.)  The Rosie macro `findall`
provides a shorthand for grep's behavior, as shown in the following example:

<pre>
$ cat test/resolv.conf
#
# This is an example file, hand-generated for testing rosie.
# Last update: Wed Jun 28 16:58:22 EDT 2017
# 
domain abc.aus.example.com
search ibm.com mylocaldomain.myisp.net example.com
nameserver 192.9.201.1
nameserver 192.9.201.2
nameserver fde9:4789:96dd:03bd::1

$ grep '.com' test/resolv.conf
domain abc.aus.example.com
search ibm.com mylocaldomain.myisp.net example.com
$ rosie grep '".com"' test/resolv.conf
domain abc.aus.example.com
search ibm.com mylocaldomain.myisp.net example.com
$ rosie match 'findall:".com"' test/resolv.conf
domain abc.aus.example<b>.com</b>
search ibm<b>.com</b> mylocaldomain.myisp.net example<b>.com</b>
$ 
</pre>

Notice that Rosie's `grep` command outputs the lines that contain a match (like
Unix grep does), but that Rosie's `match` command outputs using Rosie's `-o
color` option.  Because the pattern `".com"` is not assigned a specific color,
it is printed in the default color but in bold font.


### Matching the entire input line with nothing left over

Rosie is happy to match the first part of a line and ignore the rest.  Often, this is a good thing, but not always.  If you want to be sure that the entire input matches your pattern with no input left over, use the "end of input" pattern, `$`.

### Matching starts at the first character of the line

The Rosie Pattern Engine begins matching with the first character of the input.
(When you want to search for a match, use the `find` macro.)  Also, remember
that the token boundary `~` can be used to skip over whitespace, e.g.

``` 
$ rosie repl
Rosie> import num
Rosie> .debug off
Debug is off
Rosie> .match num.int "    321"
No match  [Turn debug on to show the trace output]
Rosie> .match ~ num.int "    321"
{"data": "    321", 
 "e": 8, 
 "s": 1, 
 "subs": 
   [{"data": "321", 
     "e": 8, 
     "s": 5, 
     "type": "num.int"}], 
 "type": "*"}
Rosie> 
```

### Further reading

* The full [RPL Language Specification](rpl.md) is a guide to all of RPL.
* See also the [Command Line Interface manual](man/rosie.html) and the interactive [REPL (read-eval-print loop)](repl.md) documentation.
* See also the [Standard Library documentation](standardlib.md).  The RPL "standard library" is bundled with Rosie and contains many pre-defined patterns.



