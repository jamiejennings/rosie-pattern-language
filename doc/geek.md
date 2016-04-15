<!--  -*- Mode: GFM; -*-                                 -->
<!--                                                     -->
<!-- Notes on Rosie for PL (and maybe general CS) geeks  -->
<!-- (c) 2016, Jamie A. Jennings                         -->

# Notes for PL folk

*Disclaimer:* In these informal notes, as well as in other posted material, I speak for myself, and not on behalf of IBM.

## Parser combinators for the masses?

Rosie Pattern Language (RPL) is a language of parser combinators.  The operators in RPL allow the construction of Parsing Expression Grammars (PEGs).  While  PEGs have been around for a few decades, and parser combinators much longer than that, neither seems to have been widely adopted.  Together, though, they are a good foundation for textual pattern matching.

Parsers specified with combinators (parsing functions) are generally considered well-structured, and easy to read and maintain.  By contrast, regular expressions (specifically the modern "regex" which contain many non-regular extensions) are considered very hard to read and maintain.  When it comes to writing parsers (or patterns), my experience suggests that PEGs are no more difficult to learn than regex.  Many concepts are common to both matching technologies, and though the differences may at first seem odd to regex users, one gets used to them.  After all, regex users had to learn regex concepts and syntax, not to mention the quirks and variations across the myriad regex implementations.

> *Some people, when confronted with a problem, think "I know, I'll use regular expressions."  Now they have two problems.*
> [Jamie Zawinski](https://en.wikipedia.org/wiki/Jamie_Zawinski)

One goal of the Rosie Pattern Language is to make PEG parsers/patterns [*(terminology note)*](#terminology) easier to write than their equivalent regex.  I do not expect to be able to measure progress towards this goal, however, as regex are so profoundly entrenched in programming culture as to be instantly familiar.  Indeed, at least one programming language, Perl, can be viewed as a decades-long accretion of features around regex.  (Contrast with the simplicity of the awk language.)

> "In my experience the hardest part is to get the regular expressions for parsing the log files right" says the author of [Grok Constructor](http://grokconstructor.appspot.com).

In any event, it is my hope that RPL will be relatively easy to write when compared to regex.  And I have confidence it will be easier to read and maintain than would a collection of regular expressions.  In this narrow sense, perhaps, I hope RPL brings the expressiveness of parser combinators to the masses.

At the same time, general programming with parser combinators can be challenging, in large part due to the large class of languages that can be recognized by recursive descent parsers (of which parser combinators are an example).  Left recursion, grammar ambiguities, and possible exponential parsing time (due to unrestricted backtracking) are some of the challenges.  But we can avoid these with PEGs.  Specifically, a PEG cannot contain left recursion (and it is possible to detect it); a PEG cannot be ambiguous; and PEGs admit linear time parsing (using "packrat parsers" or a "parsing virtual machine").

So we have a grammar formalism (PEG) that recognizes a useful subset of the Context-Free Languages (judging by the PEG literature) and a modular, structured way to read, write, and maintain parsers (via parser combinators).  The Rosie Pattern Language is an attempt to combine PEGs and parser combinators, reify the result in a somewhat elegant language, and add some support for parser/pattern development.  (The latter is represented by the read-eval-print loop of the Rosie Pattern Engine, as well as features like packages with their own namespaces.)

Maybe with RPL, more parsing power will in the hands of the masses of people who need parsers/patterns to extract useful information from textual data.

> <a name="terminology"></a>
> *A note on terminology:*

> Obviously, I chose to describe RPL expressions as *patterns* and not *parsers*, following the established regex terminology.  Partly this is because patterns sound easier to write than do parsers, at least for many programmers.  But the term is also an allusion to the 1977 architecture book, *A Pattern Language*.  Writing about the design of buildings and homes, the authors say of their work:

> > "Each solution is stated in such a way that it gives the essential field of relationships needed to solve the problem, but in a very general and abstract way -- so that you can solve the problem for yourself, in your own way, by adapting it to your preferences, and the local conditions at the place where you are making it."

> Rephrased to describe Rosie, I'd say that Rosie Pattern Language gives the essential tools needed to solve a class of problems, but in a very general and abstract way, so that you can solve information extraction problems for yourself, adapting RPL patterns to your needs and your data."

## In-line tokenization

I want to say just a few words about how Rosie does tokenization.  Natural language processing (NLP) approaches to information extraction typically tokenize the input first, and then parse in a (conceptual, perhaps) second pass.  Traditional parsers for programming languages also consume a stream of tokens; a lexer is employed to transform program text into tokens.

Parsing Expression Grammars (PEGs) are sometimes called "scannerless parsers", though, because they can perform lexical analysis (scanning) and parsing in one pass.  Scannerless parsing seems appropriate for a tool like Rosie that will process a great variety of data formats, because we do not expect much lexical regularity from one data source to another.  A scannerless approach means the user has to learn only one language (RPL) and not two (i.e. the specification languages for both a lexer and a parser).

And that is my point about tokenization in Rosie: it occurs in-line.  RPL has a pattern definition for "token boundary", conceptually like the `\b` (word boundary) in regex.  When a pattern (e.g. `common.number`) is used in a tokenized context in RPL, the Rosie Pattern Engine looks for a token boundary at the start and end of the number.  So the pattern `(common.number)+` will match a list of numbers such as these four: "1 3.1 0x0FA -6".  By contrast, the pattern `{common.number}+` will match only the initial "1" from "1 3.1 0xFA -6", because the braces around `common.number` put Rosie in untokenized (also called *raw*) mode.

One advantage to in-line tokenization is the ability to choose between matching a string exactly or matching its tokens.  The pattern `"A quick brown fox"` will match only that exact sequence of characters, spaces included.  If the spacing in the data may vary, then a better pattern to use might be `"A" "quick" "brown" "fox"`, which ignores all inter-token whitespace, including tabs and newlines.


## Self-hosting

It is a milestone in compiler development when a compiler can compile itself, which is called "self-hosting".  Future versions of the compiler can then be written in the language it compiles.  RPL is not a general purpose programming language; it is a domain-specific language for parsing that is not Turing-complete.  But of course it is possible to write a parser for RPL in [(about 60 lines of) RPL](../src/rosie-core.rpl).

The Rosie Pattern Engine was made self-hosting when the original hand-coded RPL parser (in Lua, using the LPEG library) was relegated to parsing only the definition of RPL written in RPL.  This definition is the core of RPL, in the sense that RPL syntax can now be extended or modified by writing or changing the RPL definition of the language.  Of course, to extend the language (beyond the syntax), one must also modify the RPL compiler.  I have a future goal of writing an interface through which the RPL compiler can be easily extended.  The literature on extensible compilers is rich, and the domain of Rosie (parsing data) is such that user-written compiler extensions would be fruitful.


## DWIM

DWIM stands for "do what I mean" and was originally used to describe user interfaces that tolerated user errors.  Later, in the context of the development of Emacs, DWIM came to mean "do the right thing" in the context in which the user is working.  For example, the TAB key will simply insert a tab into a text document in Emacs, but TAB will automatically compute the right amount of spaces to indent code when editing most programming languages (and other file formats).

The Rosie Pattern Language has some quirks for which I can only apologize and appeal to the DWIM philosophy.  A prime example is that RPL expressions are *mostly* (but not always) meant to match tokens.  RPL automatically tokenizes input so that the user does not have to write a token boundary symbol (like the regex `\b`) between pattern components.  But RPL lets one put an expression in curly braces `{...}` to disable tokenization -- the default mode being tokenized.  When it comes to quantified expressions like `x*` or `x+`, however, RPL treats `x` in this expression as **not tokenized**.  I.e. `"a"+` matches "aaa", while `("a")+` matches "a a a".  (Recall that parentheses `(...)` create a tokenized group in RPL.)

The choice to force the user to write `("a")+` to mean "a series of *a*'s as separate tokens" is, very loosely speaking, a DWIM choice, but only because we are so familiar with regular expression syntax and conventions.

In making this choice, I am hypothesizing that most people will write `[:alnum:]+` when they want to match a sequence of alphanumeric characters with no intertoken space, and similarly `"a"*` to mean a possibly-empty sequence of *a*'s like "aaaa".

This one area of RPL, quantified expressions, therefore has a special interpretation regarding tokenization, which is that the matching will be attempted in "raw mode", i.e. untokenized mode.

Good languages have very few "special" rules, or exceptions to general rules.  For a wonderful example of programming language "regularity" (consistency, orthogonality), look at a Scheme language specification from the 1990's, e.g. [R4RS](https://people.csail.mit.edu/jaffer/r4rs.pdf).  (Scheme has since grown some, though at this rate it will be many decades before it resembles Common Lisp.)  So why have this "special rule" in RPL regarding quantified expressions and tokenization?  Only because I think it's better in this specific instance for Rosie to do what the user *meant* when they used that `*` or `+`, even at the cost of a "special rule" to remember.  In other words, DWIM.


## Performance

To process large quantities of text input, a parser must be reasonably fast.  In theory, regular expressions match or fail in time linear in the size of the input text.  In practice, though, modern regex engines have relatively naive implementations.  This includes those in Perl, PCRE, Java, Python, and many other languages and libraries.  Instead of the linear-time approach of simulating an NFA, they use a backtracking algorithm which can require time *exponential* in the size of the input.  The edge cases that require exponential time are not esoteric; they can be seen in practice, e.g. when parsing CSV files.

Now, maybe only naively written regex will require exponential time.  Such regex make heavy use of `(.*)` and can be (should be) re-written.  However, these kinds of regex (requiring exponential time) are seen with striking frequency "in the wild".  

> "People with little regex experience have surprising skill at coming up with exponentially complex regular expressions."
> [Jan Goyvaerts](http://www.regular-expressions.info/catastrophic.html)

For example, the fragment `(.*?,)` appears in many regex solutions for parsing CSV files, such as this one `^((.*?,)+)(.*)$` to match a variable number of fields.  A truly naive (and unsuccessful) attempt would probably use `^(.*,)+(.*)$` instead, in which `.*` is greedy, as opposed to a successful solution using `.*?`, in which the question mark modifies the `.*` to prefer short alternatives.  Even this not-so-naive approach can require exponential time when searching for field data that does not appear in the CSV line, as shown in [this example](http://www.regular-expressions.info/catastrophic.html).  In another example, Russ Cox graphs the exponential run-time and observes:

> "Notice that Perl requires over sixty seconds to match a 29-character string" says Russ Cox, researcher at Google, Bell Labs.
> (https://swtch.com/~rsc/regexp/regexp1.html)

So we have a language, regex, in which users often write patterns that occasionally require exponential time, depending on the input data.  When processing large and diverse data sets, the probability of encountering "pathological" input data surely increases unacceptably.  In a data processing pipeline in which each stage consumes microseconds per line of input, can you afford one stage to take 10's of seconds on certain kinds of input?

I prefer the predictability of a linear time matching algorithim.  For this and other reasons (which are explained elsewhere), I chose the PEG formalism over the regex one.  But what if my linear time PEG algorithm runs really slowly, albeit linearly?

The PEG implementation I chose is [LPEG](http://www.inf.puc-rio.br/~roberto/lpeg/).  In this [paper on LPEG](http://www.inf.puc-rio.br/~roberto/docs/peg.pdf), Ierusalimschy describes an elegant virtual machine for parsing using PEGs.  The approach yields a linear time matching algorithm that, due to optimizations, often requires only constant space (rather than linear space).  Moreover, he notes that the implementation does very well in benchmarks.

(Interestingly, the paper makes a case against parser combinators, because as functions, they are opaque and difficult to analyze.  RPL attempts to overcome that limitation by providing helpful pattern development tools (e.g. the repl, the `eval` capability) as well as by leveraging the LPEG implementation under the covers.)

Ok... we have a linear time implementation of PEG-based matching with a low enough constant to be practical.  Now, what about the rest of the Rosie Pattern Engine?  The RPL compiler produces LPEG expressions, and the loop that processes data spends a lot of time in the LPEG library.  This should lend Rosie a respectable performance profile, although no formal benchmarks have been run (yet).

The RPL compiler is admittedly quite slow, sometimes requiring almost a quarter of a second on my MacBook Pro.  However, the compiler has had no optimizations applied.  There are many assertions (which in Lua are expensive); there are many table references to frequently used functions; the compiler does not save compiled RPL between sessions (yet); I have not tried LuaJIT.  These and other optimizations should bring the compile time for a few hundred pattern definitions down considerably.  Compiler performance is not a high priority at this stage in Rosie development.

---
*Disclaimer:* In these informal notes, as well as in other posted material, I speak for myself, and not on behalf of IBM.
