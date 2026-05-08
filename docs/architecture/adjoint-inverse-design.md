# Adjoint Inverse Design

FiberLab is a Julia API for adjoint-based inverse design in nonlinear fiber
systems. The API is organized around the adjoint contract, not around one
reference experiment. Built-in physics helpers are examples that use the same
contracts available to notebook code.

## Core Contract

An adjoint experiment has one execution contract:

```text
optimizer coordinates
  -> control decode
  -> forward fiber propagation
  -> objective cost
  -> objective terminal adjoint
  -> adjoint propagation
  -> physical gradient
  -> control pullback
  -> optimizer update
```

New controls and objectives enter through this contract.

The list of built-in controls is not a menu of what the API can do. FiberLab
does not inspect or privilege the decoded control type: it can be a vector,
named tuple, dictionary-like structure, or researcher-defined domain object.
Only the contract matters.

## Controls

A control map owns the relationship between optimizer coordinates and physical
simulation inputs. It must decode optimizer coordinates into physical controls
and pull physical gradients back to optimizer coordinates.

For a linear phase basis, if `phi = B * c`, the pullback is `B' * grad_phi`.
This allows a researcher to provide a basis without FiberLab hardcoding every
possible basis family.

## Objectives

An adjoint objective owns the scalar cost and the terminal adjoint seed. Built-in
objectives provide their own terminal adjoints. A custom objective can
participate in gradient-based adjoint optimization only when it declares the
terminal adjoint or is composed from primitives whose adjoints FiberLab owns.

## Multivariable Design

Multivariable optimization is a collection of continuous control blocks packed
into one optimizer vector. Each block decodes its slice of the vector and pulls
back its slice of the gradient. Ablation studies compare controlled subsets of
these blocks; discrete on/off variable selection is a study layer, not the core
adjoint optimizer.

## Figures And Evidence

Figures are part of the contract. Regimes, controls, objectives, and
verification settings request named figure or artifact hooks. A completed run
should expose those hooks through a result object so notebooks can ask for
figures by meaning rather than by filename.

## Defensive Rules

- Gradient-based solvers require objective terminal adjoints.
- Gradient-based solvers require control pullbacks.
- Shape, unit, bound, and finite-value checks happen before expensive runs.
- Finite differences are verification tools, not the primary route for
  high-dimensional optimization.
- Experimental contracts can be planned and inspected before trusted execution.
