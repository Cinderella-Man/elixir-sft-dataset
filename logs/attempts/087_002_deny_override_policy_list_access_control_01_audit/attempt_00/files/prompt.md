Write me an Elixir module called `AccessPolicy` that evaluates authorization requests against an **ordered-independent list of policy statements** using **explicit-deny precedence** (deny always overrides allow).

Unlike a simple role-hierarchy check, there is no notion of one role being "higher" than another here. Authorization is decided purely by matching policy statements. A policy is a plain list of statement maps of this shape:

```elixir
[
  %{effect: :allow, roles: :any,             resource: :posts,    action: :read},
  %{effect: :allow, roles: [:editor, :admin], resource: :posts,    action: :write},
  %{effect: :deny,  roles: [:editor],         resource: :posts,    action: :delete},
  %{effect: :allow, roles: [:admin],          resource: :any,      action: :any},
  %{effect: :deny,  roles: :any,              resource: :settings, action: :delete}
]
```

Each statement has:

- `:effect` — `:allow` or `:deny` (default to `:allow` if the key is missing).
- `:roles` — a single role atom, a list of role atoms, or the atom `:any` (matches every role). Defaults to `:any` if missing.
- `:resource` — a single resource atom, a list of resource atoms, or `:any`. Defaults to `:any`.
- `:action` — a single action atom, a list of action atoms, or `:any`. Defaults to `:any`.

A statement **matches** a request `(role, resource, action)` when the role matches the statement's `:roles`, the resource matches its `:resource`, and the action matches its `:action` (where `:any` matches everything, and a list matches when the value is a member).

I need the following public API:

- `AccessPolicy.evaluate(role, resource, action, policies)` — returns `:deny` if **any** matching statement has effect `:deny`; otherwise returns `:allow` if **any** matching statement has effect `:allow`; otherwise (nothing matches) returns `:deny` (default deny). Explicit deny must win over allow regardless of statement order in the list.
- `AccessPolicy.authorized?(role, resource, action, policies)` — convenience wrapper returning `true` when `evaluate/4` is `:allow`, else `false`.

Give me the complete module in a single file with no external dependencies.