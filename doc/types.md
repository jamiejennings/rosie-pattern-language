<!--  -*- Mode: GFM; -*-                        -->
<!--                                            -->
<!-- types.md   Notes on Rosie Pattern Language -->
<!--                                            -->
<!-- (c) 2016, Jamie A. Jennings                -->



# Notes

## Parser combinators

Rosie Pattern Language is a language of parsers and parser combinators.  If a
parser maps input text to a parse tree, then a parser combinator maps parsers
(as input) to a new parser.

Let
* `P` be the set of parsers;
* `T` be the set of parse trees;
* `C` be the set of parser combinators;

| Definition                          | Description                                              |
|-------------------------------------|----------------------------------------------------------|
|  `P: text -> {T \| true \| false}`  | parser produces tree or succeeds with no output or fails |
|  `C: P^n -> P, n>0`                 | n-ary parser combinator                                  |


### Built-in combinators

The set of combinators that are built into RPL are the ones from the Parsing
Expression Grammar formulation, namely for a, b in P:

Syntax   | Combinator          | Description
---------|---------------------|------------
a b      | sequence            | matches a followed by b
a / b    | ordered choice      | matches a; if a fails, then matches b
a*       | zero or more        | matches zero or more consecutive instances of a
a+       | one or more         | matches one or more consecutive instances of a
a{m,n}   | m to n repetitions  | matches at least m but no more than n consecutive instances of a
!a       | not looking at      | predicate; succeeds if a would fail
@a       | looking at          | predicate; succeeds if a would succeed
!-a      | not looking back at | predicate; succeeds if @-a fails
@-a      | looking back at     | predicate; succeeds if a matches prior input

Notes:
1. Predicates consume no input.
2. The predicates that look backward match text immediately before the current
input position.  These predicates must match text of fixed length.

### Custom combinators

To the set of built-in combinators, RPL adds a limited capability for building
custom combinators...
* alias (simple macro substitution)
* real macros ???

### Inline tokenizing

Another form of built-in combinator....


## Transformations

RPL also supports transformations of the resulting parse trees...


## Input processing directives
