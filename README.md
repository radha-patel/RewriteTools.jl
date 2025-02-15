# RewriteTools

[![Build Status](https://github.com/willow-ahrens/RewriteTools.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/willow-ahrens/RewriteTools.jl/actions/workflows/ci.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/willow-ahrens/RewriteTools.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/willow-ahrens/RewriteTools.jl)

RewriteTools.jl is a utility for term rewriting. RewriteTools.jl is a
fork of [SymbolicUtils.jl](https://github.com/JuliaSymbolics/SymbolicUtils.jl)
version 1.17, preserving and simplifying only the functionality related to term
rewriting. The semantics of rewriter objects is different, and new ``expanders'' have been added which enable program enumeration. RewriteTools.jl is intended for use with custom ASTs that have syntax
which implements
[SyntaxInterface.jl](https://github.com/willow-ahrens/SyntaxInterface.jl).

## Rule-based rewriting

Rewrite rules match and transform an expression. A rule is written using the `@rule` macro and creates a callable `Rule` object.

### Basics of rule-based term rewriting in RewriteTools

Here is a simple rewrite rule, that uses formula for the double angle of the sine function:

```julia:rewrite1
using RewriteTools

@syms w z α::Real β::Real

(w, z, α, β) # hide

r1 = @rule sin(2(~x)) => 2sin(~x)*cos(~x)

r1(sin(2z))
```

The `@rule` macro takes a pair of patterns -- the _matcher_ and the _consequent_ (`@rule matcher => consequent`). If an expression matches the matcher pattern, it is rewritten to the consequent pattern. `@rule` returns a callable object that applies the rule to an expression.

`~x` in the example is what is a **slot variable** named `x`. In a matcher pattern, slot variables are placeholders that match exactly one expression. When used on the consequent side, they stand in for the matched expression. If a slot variable appears twice in a matcher pattern, all corresponding matches must be equal (as tested by `Base.isequal` function). Hence this rule says: if you see something added to itself, make it twice of that thing, and works as such.

If you try to apply this rule to an expression with triple angle, it will return `nothing` -- this is the way a rule signifies failure to match.
```julia:rewrite2
r1(sin(3z)) === nothing
```

Slot variable (matcher) is not necessary a single variable

```julia:rewrite3
r1(sin(2*(w-z)))
```

but it must be a single expression

```julia:rewrite4
r1(sin(2*(w+z)*(α+β))) === nothing
```

Rules are of course not limited to single slot variable

```julia:rewrite5
r2 = @rule sin(~x + ~y) => sin(~x)*cos(~y) + cos(~x)*sin(~y);

r2(sin(α+β))
```

If you want to match a variable number of subexpressions at once, you will need a **segment variable**. `~~xs` in the following example is a segment variable:

```julia:rewrite6
@syms x y z
@rule(+(~~xs) => ~~xs)(x + y + z)
```

`~~xs` is a vector of subexpressions matched. You can use it to construct something more useful:

```julia:rewrite7
r3 = @rule ~x * +(~~ys) => sum(map(y-> ~x * y, ~~ys));

r3(2 * (w+w+α+β))
```

Notice that the expression was autosimplified before application of the rule.

```julia:rewrite8
2 * (w+w+α+β)
```

### Predicates for matching

Matcher pattern may contain slot variables with attached predicates, written as `~x::f` where `f` is a function that takes a matched expression and returns a boolean value. Such a slot will be considered a match only if `f` returns true.

Similarly `~~x::g` is a way of attaching a predicate `g` to a segment variable. In the case of segment variables `g` gets a vector of 0 or more expressions and must return a boolean value. If the same slot or segment variable appears twice in the matcher pattern, then at most one of the occurrence should have a predicate.

For example,

```julia:pred1
@syms a b c d

r = @rule ~x + ~~y::(ys->iseven(length(ys))) => "odd terms";

@show r(a + b + c + d)
@show r(b + c + d)
@show r(b + c + b)
@show r(a + b)
```

### Example of applying the rules to simplify expression

Consider expression `(sin(x) + cos(x))^2` that we would like simplify by applying some trigonometric rules. First, we need rule to expand square of `sin(x) + cos(x)`. First we try the simplest rule to expand square of the sum and try it on simple expression
```julia:rewrite9
using SymbolicUtils

@syms x::Real y::Real

sqexpand = @rule (~x + ~y)^2 => (~x)^2 + (~y)^2 + 2 * ~x * ~y

sqexpand((sin(x) + cos(x))^2)
```

Fortunately rules may be [chained together](#chaining rewriters) into more sophisticated rewriters to avoid manual application of the rules.


## Composing rewriters

A rewriter is any callable object which takes an expression and returns an expression
or `nothing`. If `nothing` is returned that means there was no changes applicable
to the input expression. The Rules we created above are rewriters.

The `RewriteTools.Rewriters` module contains some types which create and transform
rewriters.

- `Empty()` is a rewriter which always returns `nothing`
- `Chain(itr)` chain an iterator of rewriters into a single rewriter which applies
   each chained rewriter in the given order.
   If a rewriter returns `nothing` this is treated as a no-change.
- `RestartedChain(itr)` like `Chain(itr)` but restarts from the first rewriter once on the
   first successful application of one of the chained rewriters.
- `IfElse(cond, rw1, rw2)` runs the `cond` function on the input, applies `rw1` if cond
   returns true, `rw2` if it returns false
- `If(cond, rw)` is the same as `IfElse(cond, rw, Empty())`
- `Prewalk(rw; threaded=false, thread_cutoff=100)` returns a rewriter which does a pre-order 
   (*from top to bottom and from left to right*) traversal of a given expression and applies 
   the rewriter `rw`. `threaded=true` will use multi threading for traversal.
   Note that if `rw` returns `nothing` when a match is not found, then `Prewalk(rw)` will
   also return nothing unless a match is found at every level of the walk. If you are
   applying multiple rules, then `Chain` already has the appropriate passthrough behavior.
   If you only want to apply one rule, then consider using `PassThrough`.
   `thread_cutoff` 
   is the minimum number of nodes in a subtree which should be walked in a threaded spawn.
- `Postwalk(rw; threaded=false, thread_cutoff=100)` similarly does post-order 
   (*from left to right and from bottom to top*) traversal.
- `Fixpoint(rw)` returns a rewriter which applies `rw` repeatedly until there are no changes to be made.
- `PassThrough(rw)` returns a rewriter which if `rw(x)` returns `nothing` will instead
   return `x` otherwise will return `rw(x)`.

### Chaining rewriters

Several rules may be chained to give chain of rules. Chain is an array of rules which are subsequently applied to the expression.

To check that, we will combine rules from [previous example](#example of applying the rules to simplify expression) into a chain

```julia:composing1
using RewriteTools
using RewriteTools.Rewriters

sqexpand = @rule (~x + ~y)^2 => (~x)^2 + (~y)^2 + 2 * ~x * ~y
pyid = @rule sin(~x)^2 + cos(~x)^2 => 1

csa = Chain([sqexpand, pyid])

csa((sin(x) + cos(x))^2)
```

Important feature of `Chain` is that it returns the expression instead of `nothing` if it doesn't change the expression

```julia:composing2
Chain([@rule sin(~x)^2 + cos(~x)^2 => 1])((sin(x) + cos(x))^2)
```

it's important to notice, that chain is ordered, so if rules are in different order it wouldn't work the same as in earlier example

```julia:composing3
cas = Chain([pyid, sqexpand])

cas((sin(x) + cos(x))^2)
```
since Pythagorean identity is applied before square expansion, so it is unable to match squares of sine and cosine.

One way to circumvent the problem of order of applying rules in chain is to use `RestartedChain`

```julia:composing4
using RewriteTools.Rewriters: RestartedChain

rcas = RestartedChain([pyid, sqexpand])

rcas((sin(x) + cos(x))^2)
```

It restarts the chain after each successful application of a rule, so after `sqexpand` is hit it (re)starts again and successfully applies `pyid` to resulting expression.

You can also use `Fixpoint` to apply the rules until there are no changes.

```julia:composing5
Fixpoint(cas)((sin(x) + cos(x))^2)
```
