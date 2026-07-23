# Specification: `AccessPolicy` — Deny-Override Policy List Evaluation

## Overview

This document specifies an Elixir module named `AccessPolicy` that evaluates authorization requests against an **order-independent list of policy statements** using **explicit-deny precedence** (deny always overrides allow).

Unlike a simple role-hierarchy check, there is no notion of one role being "higher" than another in this model. Authorization is decided purely by matching policy statements. A policy is a plain list of statement maps of this shape:

```elixir
[
  %{effect: :allow, roles: :any,             resource: :posts,    action: :read},
  %{effect: :allow, roles: [:editor, :admin], resource: :posts,    action: :write},
  %{effect: :deny,  roles: [:editor],         resource: :posts,    action: :delete},
  %{effect: :allow, roles: [:admin],          resource: :any,      action: :any},
  %{effect: :deny,  roles: :any,              resource: :settings, action: :delete}
]
```

## Statement structure

Each statement has the following keys:

- `:effect` — `:allow` or `:deny`. Defaults to `:allow` if the key is missing.
- `:roles` — a single role atom, a list of role atoms, or the atom `:any` (matches every role). Defaults to `:any` if missing.
- `:resource` — a single resource atom, a list of resource atoms, or `:any`. Defaults to `:any`.
- `:action` — a single action atom, a list of action atoms, or `:any`. Defaults to `:any`.

A statement **matches** a request `(role, resource, action)` when the role matches the statement's `:roles`, the resource matches its `:resource`, and the action matches its `:action` — where `:any` matches everything, and a list matches when the value is a member.

## API

The module must expose the following public functions:

- `AccessPolicy.evaluate(role, resource, action, policies)` — returns `:deny` if **any** matching statement has effect `:deny`; otherwise returns `:allow` if **any** matching statement has effect `:allow`; otherwise (nothing matches) returns `:deny` (default deny).
- `AccessPolicy.authorized?(role, resource, action, policies)` — a convenience wrapper returning `true` when `evaluate/4` is `:allow`, else `false`.

## Edge cases

- Explicit deny must win over allow regardless of statement order in the list.
- A request that matches no statement at all resolves to `:deny` (default deny).
- Missing keys fall back to their documented defaults: `:effect` to `:allow`, and `:roles`, `:resource`, and `:action` each to `:any`.

## Delivery

The complete module is to be delivered in a single file with no external dependencies.
