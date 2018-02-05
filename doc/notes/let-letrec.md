## Problem statement

Today's grammar blocks (version 1.0.0-alpha-10) have several problems:

1. They allow only one binding to be exposed to the outer scope (the first one).
2. That binding is not visually (syntactically) distinct in any way.
3. The syntax does not lend itself to use as an grammar expression.
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
* Current uses of `grammar` must be rewritten.

``` 
z = let x="foo"
        y="bar" x?
    in {x y}
```

NEGATIVES:

* Accidental recursion at top level could be very difficult to debug.  Probably,
  recursion should be explicit.
  
  
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
* The approach requires no new keywords.

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
  enabled by the user.
* Add a variant of the current `grammar` which uses `in`.
* Make it a (temporary) restriction that there can be only one binding between
  `in` and `end`.
* Disable, in the compiler, the current `grammar` syntax, in which every binding
  is exposed, until we can support this in the implementation.  Parse it, but
  return an informative error message (and maybe the corrected version of the
  form?).
* Write the parsers for `local`/`in`/`end` and `local`/`in` to make sure they
  are mellifluous and practical constructs.
* Enhance the RPL syntax highlighting (for emacs) to understand these changes.
* Maybe release a Python script that fixes old uses of `grammar`?

