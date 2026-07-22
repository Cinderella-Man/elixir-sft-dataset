# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir module called `AccessPolicy` that evaluates authorization requests against an **ordered-independent list of policy statements** using **explicit-deny precedence** (deny always overrides allow).

Unlike a simple role-hierarchy check, there is no notion of one role being "higher" than another here. Authorization is decided purely by matching policy statements. A policy is a plain list of statement maps of this shape:

```elixir
[
  %{effect: :allow, roles: :any, resource: :posts, action: :read},
  %{effect: :allow, roles: [:editor, :admin], resource: :posts, action: :write},
  %{effect: :deny, roles: [:editor], resource: :posts, action: :delete},
  %{effect: :allow, roles: [:admin], resource: :any, action: :any},
  %{effect: :deny, roles: :any, resource: :settings, action: :delete}
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

## Module under test

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

  defp field_match?(:any, _value), do: true
  defp field_match?(expected, value) when is_list(expected), do: value in expected
  defp field_match?(expected, value), do: expected == value
end
```
