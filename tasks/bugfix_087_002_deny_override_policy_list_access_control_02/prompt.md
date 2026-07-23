# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

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

## The buggy module

```elixir
defmodule AccessPolicy do
  @moduledoc """
  Policy-statement authorization with explicit-deny precedence.

  Authorization is decided by matching a request `{role, resource, action}`
  against a flat, order-independent list of statement maps. There is no role
  hierarchy: a request is `:allow`ed only when a matching allow statement
  exists and no matching deny statement exists.

  ## Statement shape

      %{
        effect:   :allow | :deny,          # default :allow
        roles:    atom | [atom] | :any,    # default :any
        resource: atom | [atom] | :any,    # default :any
        action:   atom | [atom] | :any     # default :any
      }

  ## Decision procedure

    1. If any matching statement has effect `:deny` -> `:deny`.
    2. Else if any matching statement has effect `:allow` -> `:allow`.
    3. Else (no match) -> `:deny` (default deny).

  Explicit deny always wins over allow, independent of list order.
  """

  @type effect :: :allow | :deny
  @type statement :: map()

  @doc """
  Evaluates a request against `policies`, returning `:allow` or `:deny`.
  """
  @spec evaluate(atom(), atom(), atom(), [statement()]) :: effect()
  def evaluate(role, resource, action, policies) when is_list(policies) do
    matching = Enum.filter(policies, &matches?(&1, role, resource, action))

    cond do
      Enum.any?(matching, &(effect_of(&1) == :deny)) -> :deny
      Enum.any?(matching, &(effect_of(&1) == :allow)) -> :allow
      true -> :deny
    end
  end

  @doc """
  Returns `true` when `evaluate/4` yields `:allow`, `false` otherwise.
  """
  @spec authorized?(atom(), atom(), atom(), [statement()]) :: boolean()
  def authorized?(role, resource, action, policies) do
    evaluate(role, resource, action, policies) == :allow
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp matches?(stmt, role, resource, action) do
    field_match?(Map.get(stmt, :roles, :any), role) and
      field_match?(Map.get(stmt, :resource, :any), resource) and
      field_match?(Map.get(stmt, :action, :any), action)
  end

  defp effect_of(stmt), do: Map.get(stmt, :effect, :allow)

  defp field_match?(:any, _value), do: false
  defp field_match?(expected, value) when is_list(expected), do: value in expected
  defp field_match?(expected, value), do: expected == value
end
```

## Failing test report

```
6 of 12 test(s) failed:

  * test basic matching allows when a matching allow statement exists
      
      
      Expected truthy, got false
      code: assert AccessPolicy.authorized?(:viewer, :posts, :read, @policies)
      arguments:
      
               # 1
               :viewer
      
               # 2
               :posts
      
               # 3
               :read
      
               # 4
               [%{action: :read, resource: :posts, effect: :allow, roles: :any}, %{action: :write, resource: :posts, effect: :allow, roles: [:editor, :admin]}, %{action: :delete, resource: :posts, effect: :deny, roles: [:editor]}, %{action: :any, resource: :any, effect: :allow, roles: [:a

  * test explicit-deny precedence deny overrides a wildcard admin allow
      
      
      Expected truthy, got false
      code: assert AccessPolicy.authorized?(:admin, :settings, :read, @policies)
      arguments:
      
               # 1
               :admin
      
               # 2
               :settings
      
               # 3
               :read
      
               # 4
               [%{action: :read, resource: :posts, effect: :allow, roles: :any}, %{action: :write, resource: :posts, effect: :allow, roles: [:editor, :admin]}, %{action: :delete, resource: :posts, effect: :deny, roles: [:editor]}, %{action: :any, resource: :any, effect: :allow, roles:

  * test wildcard :any semantics admin wildcard allow grants unrelated resources
      
      
      Expected truthy, got false
      code: assert AccessPolicy.authorized?(:admin, :posts, :delete, @policies)
      arguments:
      
               # 1
               :admin
      
               # 2
               :posts
      
               # 3
               :delete
      
               # 4
               [%{action: :read, resource: :posts, effect: :allow, roles: :any}, %{action: :write, resource: :posts, effect: :allow, roles: [:editor, :admin]}, %{action: :delete, resource: :posts, effect: :deny, roles: [:editor]}, %{action: :any, resource: :any, effect: :allow, roles: [

  * test wildcard :any semantics :any roles matches every role
      
      
      expected viewer to read posts via :any roles
      

  (…2 more)
```
