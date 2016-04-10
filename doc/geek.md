<!--  -*- Mode: GFM; -*-                                 -->
<!--                                                     -->
<!-- Notes on Rosie for PL (and maybe general CS) geeks  -->
<!-- (c) 2016, Jamie A. Jennings                         -->

# Notes for PL folk

## Parser combinators for the masses?

Rosie Pattern Language (RPL) is a language of parser combinators.  The operators in RPL allow the construction of Parsing Expression Grammars (PEGs).  While  PEGs have been around for a few decades, and parser combinators much longer than that, neither seems to have been widely adopted.  Together, though, they are a good foundation for textual pattern matching.

Parsers specified with combinators (parsing functions) are generally considered well-structured, and easy to read and maintain.  By contrast, regular expressions (specifically the modern "regex" which contain many non-regular extensions) are considered very hard to read and maintain.  When it comes to writing parsers (or patterns), my experience suggests that PEGs are no more difficult to learn than regex.  Many concepts are common to both matching technologies, and though the differences may at first seem odd to regex users, one gets used to them.  After all, regex users had to learn regex concepts and syntax, not to mention the quirks and variations across the myriad regex implementations.

One goal of the Rosie Pattern Language is to make parsers/patterns easier to write than their equivalent regex.  I do not expect to be able to measure progress towards this goal, however, as regex are so profoundly entrenched in programming culture.  Indeed, at least one programming language, Perl, can be viewed as an accretion of features around regex.  (Contrast with the simplicity of the awk language.)

[Perl to the rescue?  Now they have *two* problems!](http://imgs.xkcd.com/comics/regular_expressions.png)

In any event, it is my hope that RPL will be relatively easy to write when compared to regex.  And I have confidence it will be easier to read and maintain than would a collection of regular expressions.  In this narrow sense, perhaps, I hope RPL brings the expressiveness of parser combinators to the masses.

At the same time, general programming with parser combinators can be challenging, in large part due to the large class of languages that can be recognized by recursive descent parsers (of which parser combinators are an example).  Left recursion, grammar ambiguities, and possible exponential parsing time (due to unrestricted backtracking) are some of the challenges.  But we can avoid these with PEGs.  Specifically, a PEG cannot contain left recursion (and it is possible to detect it); a PEG cannot be ambiguous; and PEGs admit linear time parsing (using "packrat parsers").

So we have a grammar formalism (PEG) that recognizes a useful subset of the Context-Free Languages (judging by the PEG literature) and a modular, structured way to read, write, and maintain parsers (via parser combinators).  The Rosie Pattern Language is an attempt to combine PEGs and parser combinators, reify the result in a somewhat elegant language, and add some support for parser/pattern development.  (The latter is represented by the read-eval-print loop of the Rosie Pattern Engine, as well as features like packages with their own namespaces.)


## DWIM

Forthcoming

## Self-hosting

Forthcoming


## Performance

Forthcoming




