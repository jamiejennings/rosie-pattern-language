<!--  -*- Mode: GFM; -*-                             -->
<!--                                                 -->
<!-- invariants.md   Notes on Rosie Pattern Language -->
<!--                                                 -->
<!-- (c) 2016, Jamie A. Jennings                     -->

# Language invariants (Sunday, June 12, 2016)

<!-- --------------------------------------------------------------------------------------------------- -->
## Notation

- <e> `::` <text> means that <e> *returns a match* when given the input string <text>
- <e1> `==` <e2> means that <e1> :: <text> iff <e2> :: <text> for all input strings <text>
- The `binding` of <id> to <exp> is the result of either *binding by assignment* (e.g. `<id> = <exp>`) or *binding by alias definition* (e.g. `alias <id> = <exp>`)
- Intermediate language is written as S-expressions with capitalized names in the operator position and one or more expressions in the operand positions
- `(EVAL <exp>)` is the result of evaluating (compiling) `<exp>`

<!-- --------------------------------------------------------------------------------------------------- -->
## Match invariants

### Bindings

0. After binding `a` to `<exp>`, `a` == `<exp>`
0. The only difference between `alias a = <exp>` and `a = <exp>` is the capture named `a` produced by matches in the latter case, i.e. in both cases `a` == `<exp>`
0. When appearing as the right hand side of a binding operator, `<exp>` is equivalent to `(<exp>)` (because tokenization is the default)
0. After binding `a` as `a = <exp>`, a reference to the identifier `a` is equivalent to substituting `(EVAL <exp>)`
0. Top-level expressions are interpreted as if they were the right hand side of an assignment to an unbound identifier

### Sequences

0. `<e1> <e2>` is interpreted as `(SEQ <e1> <e2>)`
0. `(SEQ <e1> <e2>)` :: <input> iff ... **define sequence match**
0. Sequences are right associative, and the precedence of choices and sequences is the same
0. The sequence `{<e1> <e2>}` is equivalent to `(SEQ <e1> <e2>)` (and so on for longer sequences), and is called a *untokenized sequence* (or a *raw sequence*)
0. The sequence `(<e1> <e2>)` is equivalent to `(SEQ <e1> ~ <e2>)` (and so on for longer sequences), and is called a *tokenized sequence* (or a *cooked sequence*)
0. Sequences are cooked by default

### Quantified expressions

0. A quantified expression, `<exp> <q>`, is a kind of (parameterized) non-tokenized sequence, denoted in intermediate language by `(QUANT <exp>
<q>)`, where `<exp>` is the base expression and `<q>` is the quantifier
0. `(QUANT <exp> <q>)` :: <input> iff ... **define quantifier match**
0. `<exp><q>` means `<exp> <exp> ... <exp>` for the appropriate number of `<exp>`, as per `<q>`
0. `(<exp>)<q>` means `<exp> ~ <exp> ... ~ <exp>` for the appropriate number of `<exp>`, as per `<q>`
0. `{<exp>}<q>` == `<exp><q>` == `{<exp><q>}` == `(<exp><q>)` == `(QUANT <exp> <q>)`
0. Note that `(<exp>)<q>` !== `(<exp><q>)`.
0. All expressions are considered untokenized except for tokenized expressions `(<exp>)` and not explcitly tokenized sequences `<e1> <e2>`.

<!-- 0. The following kinds of expressions are *inherently considered to be untokenized sequences* (i.e. *raw*): literals, character classes, the end -->
<!--    of input identifier `$`, and the base of a quantified expression.  This means that `<exp>` == `{<exp>}` where `<exp>` is one of these -->
<!--    expressions.  This property is particularly apparent when `<exp>` appears in the quantified expression `<exp><q>` and when `<exp>` appears -->
<!--    within a choice expression. -->

### Choices

0. `(CHOICE <e1>  <e2>)` :: <input> iff ... **define choice match**
0. Choices are right associative, and the precedence of choices and sequences is the same
0. The choice `<e1> / <e2>` is interpreted as `(CHOICE <e1> <e2>)`
0. The choice `{<e1> / <e2>}` == `{<e1>} / {<e2>}` (and so on for longer choices).

0. The choice `(<e1> / <e2>)` == `(<e1>) / (<e2>)` (and so on for longer choices).

0. The choice `{(<e1>) / <e2>}` == `{<e1> ~} / {<e2>}`

0. The expression `{<e1> / <e2> <e3>}` is interpreted as `(CHOICE <e1> (SEQ <e2 <e3>))` (right associativity, equal precedence)

0. The expression `(<e1> / <e2> <e3>)` is interpreted as `(CHOICE <e1> (SEQ <e2 ~ <e3>))`
0. The expression `(<e1> / <e2> <e3>)` == `(<e1>) / (<e2> <e3>)`
0. The expression `(<e1> / <e2> <e3>)` == `(<e1>) / {<e2> ~ <e3>}`

0. The expression `(<e1> / <e2>) <e3>` == `{<e1> / <e2>} ~ <e3>`
0. The expressions `(<e1> / <e2>) <e3>` and `{<e1> / <e2>} <e3>` are interpreted as `(SEQ (CHOICE <e1> <e2>) ~ <e3>)`
0. The expressions `(<e1> / <e2>) <e3>` and `{<e1> / <e2>} <e3>` are equivalent to `({<e1> / <e2>} <e3>)` (because tokenization is the default)
0. The expressions `(<e1> / <e2>) <e3>` and `{<e1> / <e2>} <e3>` are equivalent to `{{<e1> / <e2>} ~ <e3>}` (because tokenization is the default)

### Idempotency and no-op

0. The expression `((<exp>))` is equivalent to `(<exp>)` (idempotency of tokenization)
0. The expression `{{<exp>}}` is equivalent to `{<exp>}` (idempotency of suspension of tokenization)
0. The expression `{(<exp>)}` is equivalent to `(<exp>)` (suspension of tokenization is a no-op here)
0. The expression `({<exp>})` is equivalent to `{<exp>}` (tokenization is a no-op here)

<!-- --------------------------------------------------------------------------------------------------- -->
## Capture invariants

0. The right hand side of an assignment is captured, and the capture is named for the left hand side (the identifier)
0. The right hand side of an alias definition is not captured

## Intermediate language invariants

0. `(SEQ <e_1> <e_2> ... <e_n>)` is equivalent to `(SEQ <e_1> (SEQ <e_2> ... (SEQ <e_n-1> <e_n>)))` (right association)
0. `(CHOICE <e_1> <e_2> ... <e_n>)` is equivalent to `(CHOICE <e_1> (CHOICE <e_2> ... (CHOICE <e_n-1> <e_n>)))` (right association)
