## Problem statement

Today's grammar blocks (version 1.0.0-alpha-10) have several problems:

1. They allow only one binding to be exposed to the outer scope (the first one).
2. That binding is not visually (syntactically) distinct in any way.
3. The syntax does not lend itself to use as a grammar _expression_.
4. There is no other way, today, to introduce a local scope.

We explore two design paths, each defined by whether or not we keep the current
prohibition on recursion at the top level, i.e. file scope.


## If file scope allowed recursion

Suppose we change the top level (file scope) to allow mutual recursion.

Then, the current grammar block does just one thing: It allows local bindings to
be hidden from the file scope.

Today we have:

```
grammar z={x y}
        x=“foo”
		y=“bar” x?
end
```

We could change this into:

```
let x="foo"
    y="bar" x?
in 
    z={x y}
end	  
```

POSITIVES:

* The `let` syntax allows any number of bindings to be exposed (via the `in`
  block).
* It has a fairly obvious EXPRESSION variant in which a single expression
  follows the `in`.  This syntax does not require `end`.
* The approach requires only one keyword, `let`, which replaces `grammar`.

``` 
z = let x="foo"
        y="bar" x?
    in {x y}
```

NEGATIVES:

* Accidental recursion at top level could be very difficult to debug.  Probably,
  recursion should be explicit.
* Current uses of `grammar` must be rewritten.
  
  
## If we continue to prohibit recursion in file scope

Suppose we keep the prohibition on recursion at top level (file scope).

Then, the current grammar block continues to do two things: It allows local bindings to
be hidden from the file scope, and it allows recursion among a set of bindings.

But it allows exactly one binding to be exposed to the outer scope (the first
rule, which syntactically looks like all the other rules).

Today we have:

```
grammar z={x y}
        x=“foo”
		y=“bar” x?
end
```

We could change this into:

```
grammar 
  x="foo"
  y="bar" x?
in 
  z={x y}
end	  
```

POSITIVES:

* The altered `grammar` syntax allows any number of bindings to be exposed (via
  the `in` block).
* It has a fairly obvious EXPRESSION variant in which a single expression
  follows the `in`.  This syntax does not require `end`.
* The approach requires no new keywords, assuming we would add the `in` keyword anyway.

``` 
z = grammar
      x="foo"
      y="bar" x?
    in {x y}
```

The exposed bindings could be individually made local or not:

```
grammar 
  x="foo"
  y="bar" x?
in 
  local z={x y}
  w = (z)+
end	  
```


NEGATIVES:

* The current `grammar` syntax has a new meaning, in which ALL the bindings are
  exposed to the outer scope.  Current uses of `grammar` must be rewritten.
* Still need a way to have local bindings WITHOUT recursion.  Could we give
  `local` another form?

```
a = local 
      b = “foo”
      c = “bar”
    in {b c}
```

* Or, introduce `let` for this?

```
a = let 
      b = “foo”
      c = “bar”
    in {b c}
```

## DECISION

* Keep the prohibition on recursion everywhere except where it is explicitly
  enabled by the user, using the keyword `grammar`.
* Add a variant of the current `grammar` which uses `in` to separate a possibly
  empty set of "private" block-local bindings from top-level bindings.
* Make it a (temporary) restriction that there can be only one binding between
  `in`...`end` of a grammar.
* Disable, in the compiler, the current `grammar` syntax, in which every binding
  is exposed, until we can support this in the implementation.  Parse it, but
  return an informative error message (and maybe the corrected version of the
  form?).
* Use `let` to introduce a block with "private" block-local bindings.  It's more
  clear than overloading `local`.
* Write the parsers for `let`/`in`/`end` and `let`/`in` to make sure they
  are mellifluous and practical constructs.
* Enhance the RPL syntax highlighting (for emacs) to understand these changes.
* Maybe release a Python script that fixes old uses of `grammar`?

### Statement variants 

* All bindings between `in`...`end` are top-level bindings, and can be
  optionally declared local.

* In a grammar block, the set of block-local bindings could be empty, in which
  case you can optionally leave out the `in` keyword.

* A let block with an empty set of block-local bindings is a no-op:

    let <binding1>...<bindingN> end === <binding1>...<bindingN> 

``` 
-- Top-level bindings: S, A, B (exported)
grammar
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
end

-- Top-level bindings: S (exported)
grammar
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
in
  alias S = { {"a" B} / {"b" A} / "" }
end

-- Top-level bindings: sameAB (exported)
grammar
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
in
  sameAB = S $
end

-- Top-level bindings: z (local), w (exported)
grammar 
  x="foo"	 -- The "local" keyword would be redundant here,
  y="bar" x?     -- so it is not allowed.
in 
  local z={x y}  -- Vars bound here appear in outer scope, so the 
  w = (z)+       -- "local" keyword is valid.
end	  

-- Top-level bindings: z (local), w (exported)
let
  x="foo"
  y="bar" x?
in 
  grammar
    local z={x y} w / $  
    w = (z)+
  end
end

-- Top-level bindings: w (exported)
let
  x="foo"
  y="bar" x?
in 
  grammar
    z={x y} w / $
  in
    w = (z)+
  end
end

-- Top-level bindings: z (local), w (exported)
let
  x="foo"
  alias y="bar" x?
in 
  local z={x y}
  w = (z)+
end	  

``` 

### Expression variants

* A single expression must follow `in`.  

* The point of a grammar expression is that it allows recursive bindings.
  Therefore, the expression part must be able to refer to itself, without
  referencing a name to which the expression may be ultimately bound.  As an
  expression, it may used without ever being bound directly to a name.  So, a
  grammar expression looks like a grammar block with an expression after `in`,
  and a name after the `grammar` keyword.  The name is bound within the grammar
  expression to itself.

* A let expression with an empty set of block-local bindings is a no-op:

    let <exp> === <exp>


``` 
w = grammar W   -- Syntax & semantics analogous to Scheme's "named let"
      x="foo"
      y="bar" x?
      z={x y}
    in 
      (z W)+

w = let
      x="foo"
      y="bar" x?
      z={x y}
    in 
      (z)+

w = let
      x="foo"
      y="bar" x?
      z={x y}
    in 
      (z w)+     -- !!! This will fail due to circular ref to w.

``` 
