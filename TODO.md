# To Do

## Most Urgent

### Normalisation

We need this implemented as a gatekeeper for the construction of Assertions,
and it needs to duplicate side-conditions when such refers to a multiply-used quantifier variable.
We also need to handle non-substitutable terms
(**It is now clear that n.s. indication should be part of a term itself,
and not left to be looked up in a table. Otherwise normalisation needs to take a list of
var tables as an argument**).

We need to normalise all `Assertion`s as follows:

1 `Assertion` becomes an abstract (new)type that guarantees normalisation by construction.

2 All quantifier variables must be unique, arranged by using the `Int` component of the `Identifier` datatype.

3 Any nested `Bind`s with the same type and identifier ahould be merged 

```
B tk i vs1 (B tk i vs2) ⟼  B tk i (vs1 ∪ vs2)
```

4 All free variables at the assertion top-level have a zero `Int` component.

5 All variables inside a non-substitutable term have a zero `Int` component(?).
  Should we allow n.s. terms to contain quantifiers?


### Upgrade 2

We now have to show the two following predicates are the same

```
(∃ O$_3 • (∃ O$_4 • P[O$_4/O$']∧(Q[O$_4,O$_3/O$,O$']∧R[O$_3/O$])))
(∃ O$_1 • (∃ O$_2 • P[O$_1/O$']∧(Q[O$_1,O$_2/O$,O$']∧R[O$_2/O$])))
```

Given that `O$_1`..`O$_4` are fresh w.r.t. `P`..`R`.

We need alpha-equivalence check.

With the normalisation described above, 
we then use matching to find a binding, 
which must be bijective over B varsets.

Our example normalises as follows:

```
(∃ O$_3,O$_4 • P[O$_4/O$']∧(Q[O$_4,O$_3/O$,O$']∧R[O$_3/O$]))
(∃ O$_1,O$_2 • P[O$_1/O$']∧(Q[O$_1,O$_2/O$,O$']∧R[O$_2/O$]))
```

Matching the `Bind` bodies results in the following:

```
{ O$_1 ⟼ O$_4, O$_2 ⟼ O$_3 }
```

This is a bijection.

### Factory Reset

Have `b R *` set all theories to builtin

## Upgrade No. 2

We have made this so.

```
(∃ O$_m • P[O$_m/O$']∧(∃ O$_n • Q[O$_n/O$']∧R[O$_n/O$])[O$_m/O$])
```

We now need to be able to swap nested (same) quantifiers 
and have alpha-equivalence.


## Upgrade No. 3

For simultaneous assignment we need to be able to represent
things like

`x,y$ :=  x+1,y$`

This may require `Var` to contain `GenVar` rather than `Variable`.

## Upgrade No. 4

Need to re-design `TestRendering` so we can have meaningful 
official names (`or`,`refines`) 
that map to nice symbols (`∨`,`⊒`),
rather than be called by their LaTeX names (`lor`,`sqsupseteq`).

### Phase 1.
  Hardcoded Mapping tables
  
### Phase 2.
  Mapping tables part of `REqState`,
  and hence loadable, saveable, and editable.

## Upgrade No. 5

We have an ongoing proof of Ex2.1.2 above, but it requires
a case-analysis.

The rule is, provided that `b:B`,

```
(∀ b • P)  ≡  P[true/b] ∧ P[false/b]
```

What is the best formulation of this rule?

```
 b:B ⟹ ( (∀ b • P)  ≡  P[true/b] ∧ P[false/b] )
```

or

```
(∀ b • P)  ≡  P[true/b] ∧ P[false/b],   b:B
```

or

```
(∀ b:B • P)  ≡  P[true/b] ∧ P[false/b]
```

This needs types!

## Upgrade No. 6

Need to find a way to change dependencies in a DAG.


## Robustness

### Issue 1
 
  There should be no runtime errors when starting up, regardless of the presence/absense or state of relevant files.

### Issue 2

If in one theory, if we restart a proof based in another theory, using `r`, we get the conjecture in the context of the first theory, and not that of the second. This should be fixed.



### Theory Management

In priority order:

1. Load a theory "update".
   This involves adding in new axioms and conjectures,
   but not overwriting the status of existing laws and conjectures,
   unless they have been changed.

2. Load a theory file from outside the workspace

3. Create and Populate a workspace.


In the event that a pre-existing item has changed,
confirmation for the update should be requested from the user
(a force option can also be provided).


### Files.lhs

Current focus: `Files.lhs` - needs a re-think.

`getWorkspaces` should check that it has a non-empty list of workspaces,
and return them parsed into current-flag, name and path triples.

`currentWorkspace` needs to become two different things.

One loads up the current workspace, if it exists.

Another creates and initialises a workspace.

## Features

### Substitution Handling


Added Conjecture `[P] => P[e̅/x̅]` to `UClose` and proven.




  
### Test Re-jigging

Trying to have common data and function definitions for testing. Non-trivial.

Want to support local (internal) tests within any module that does not export
all data-structure details, with some hidden by invariant-checking constructor functions.
Want lots of shorthand (partial) builders for test data for these data-structures.

To avoid cyclic module imports, we need to export shorthands from non-test modules.
Testing modules need to import the modules they test.


### Demote

 Demote can demote an axiom - it should really warn about that, or require a special argument to force it.

### Robust Load
Need to make file loading robust - no runtime failure.

* make proof loading more tolerant of read/show mismatches - allow a step to be marked as TBR (to-be-redone).

### Testing

`Substitution.lhs` looks like a good candidate for QuickCheck !

Example:  *(P\s1)s2 = P(s1;s2)* (a.k.a. `substitute` and `substComp`).

### Theory Checks

Need a way to check a theory (in context, with all its dependencies)

* all Cons have a substitutability indication in scope.

## Ongoing Issues

### Backing out of a proof step

If we use "b" after a proof step that is not reversible (just Clone?), we leave the goal unchanged,
but shorten the list of steps anyway. See `LiveProofs.undoCalcStep` (line 810 approx)

### Unique quantified variables


We need to either have unique q.v.s, or be very careful. 



## Next Task(s)


 
* LiveProof returns `(bind,local_scC)` - need to get `local_scC` into proof step.




## Quantifier Laws in proofs

## Theory Management

* law renaming

* Generating proof graph as dot/graphviz file.
  