<!--  -*- Mode: GFM; -*-                                 -->
<!--                                                     -->
<!-- Notes on Rosie for PL (and maybe general CS) geeks  -->
<!-- (c) 2016, Jamie A. Jennings                         -->

# Notes for PL folk

## Parser combinators for the masses?

Rosie Pattern Language (RPL) is a language of parser combinators.  The operators in RPL allow the construction of Parsing Expression Grammars (PEGs).  While  PEGs have been around for a few decades, and parser combinators much longer than that, neither seems to have been widely adopted.  Together, though, they are a good foundation for textual pattern matching.

Parsers specified with combinators (parsing functions) are generally considered well-structured, and easy to read and maintain.  By contrast, regular expressions (specifically the modern "regex" which contain many non-regular extensions) are considered very hard to read and maintain.  When it comes to writing parsers (or patterns), my experience suggests that PEGs are no more difficult to learn than regex.  Many concepts are common to both matching technologies, and though the differences may at first seem odd to regex users, one gets used to them.  After all, regex users had to learn regex concepts and syntax, not to mention the quirks and variations across the myriad regex implementations.

> *Some people, when confronted with a problem, think "I know, I'll use regular expressions."  Now they have two problems.*
> [Jamie Zawinski](https://en.wikipedia.org/wiki/Jamie_Zawinski)

One goal of the Rosie Pattern Language is to make PEG parsers/patterns [*(terminology note)*](#terminology) easier to write than their equivalent regex.  I do not expect to be able to measure progress towards this goal, however, as regex are so profoundly entrenched in programming culture as to be instantly familiar.  Indeed, at least one programming language, Perl, can be viewed as a decades-long accretion of features around regex.  (Contrast with the simplicity of the awk language.)

In any event, it is my hope that RPL will be relatively easy to write when compared to regex.  And I have confidence it will be easier to read and maintain than would a collection of regular expressions.  In this narrow sense, perhaps, I hope RPL brings the expressiveness of parser combinators to the masses.

At the same time, general programming with parser combinators can be challenging, in large part due to the large class of languages that can be recognized by recursive descent parsers (of which parser combinators are an example).  Left recursion, grammar ambiguities, and possible exponential parsing time (due to unrestricted backtracking) are some of the challenges.  But we can avoid these with PEGs.  Specifically, a PEG cannot contain left recursion (and it is possible to detect it); a PEG cannot be ambiguous; and PEGs admit linear time parsing (using "packrat parsers").

So we have a grammar formalism (PEG) that recognizes a useful subset of the Context-Free Languages (judging by the PEG literature) and a modular, structured way to read, write, and maintain parsers (via parser combinators).  The Rosie Pattern Language is an attempt to combine PEGs and parser combinators, reify the result in a somewhat elegant language, and add some support for parser/pattern development.  (The latter is represented by the read-eval-print loop of the Rosie Pattern Engine, as well as features like packages with their own namespaces.)

Maybe with RPL, more parsing power will in the hands of the masses of people who need parsers/patterns to extract useful information from textual data.

> <a name="terminology"></a>
> *A note on terminology*
> Obviously, I chose to describe RPL expressions as *patterns* and not *parsers*, following the established regex terminology.  Partly this is because patterns sound easier to write than do parsers, at least for many programmers.  But the term is also an allusion to the 1977 architecture book, *A Pattern Language*.  Writing about the design of buildings and homes, the authors say of their work:

> > "Each solution is stated in such a way that it gives the essential field of relationships needed to solve the problem, but in a very general and abstract way -- so that you can solve the problem for yourself, in your own way, by adapting it to your preferences, and the local conditions at the place where you are making it."

> Rephrased to describe Rosie, I'd say that Rosie Pattern Language gives the essential tools needed to solve a class of problems, but in a very general and abstract way, so that you can solve information extraction problems for yourself, adapting RPL patterns to your needs and your data."

## In-line tokenization

I want to say just a few words about how Rosie does tokenization.  Natural language processing (NLP) approaches to information extraction typically tokenize the input first, and then parse in a (conceptual, perhaps) second pass.  Traditional parsers for programming languages also consume a stream of tokens; a lexer is employed to transform program text into tokens.

Parsing Expression Grammars (PEGs) are sometimes called "scannerless parsers", though, because they can perform lexical analysis (scanning) and parsing in one pass.  Scannerless parsing seems appropriate for a tool like Rosie that will process a great variety of data formats, because we do not expect much lexical regularity from one data source to another.  A scannerless approach means the user has to learn only one language (RPL) and not two (i.e. the specification languages for both a lexer and a parser).

And that is my point about tokenization in Rosie: it occurs in-line.  RPL has a pattern definition for "token boundary", conceptually like the "\\b" (word boundary) in regex.  When a pattern (e.g. `common.number`) is used in a tokenized context in RPL, the Rosie Pattern Engine looks for a token boundary at the start and end of the number.  So the pattern `(common.number)+` will match a list of numbers such as these four: "1 3.1 0x0FA -6".  By contrast, the pattern `{common.number}+` will match only the initial "1" from "1 3.1 0xFA -6", because the braces around `common.number` put Rosie in untokenized (also called *raw*) mode.

One advantage to in-line tokenization is the ability to choose between matching a string exactly or matching its tokens.  The pattern `"A quick brown fox"` will match only that exact sequence of characters, spaces included.  If the spacing in the data may vary, then a better pattern to use might be `"A" "quick" "brown" "fox"`, which ignores all inter-token whitespace, including tabs and newlines.


## Self-hosting

Forthcoming

## DWIM

Forthcoming


## Performance

Forthcoming




