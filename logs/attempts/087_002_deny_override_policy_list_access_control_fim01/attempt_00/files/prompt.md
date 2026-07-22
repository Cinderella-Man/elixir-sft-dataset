# Implement `AccessPolicy.evaluate/4`

You are working on the `AccessPolicy` module, which evaluates authorization
requests against a flat, **order-independent** list of policy statement maps
using **explicit-deny precedence** (a matching deny always overrides a matching
allow, regardless of position in the list).

Implement the public `evaluate/4` function.

`evaluate(role, resource, action, policies)` takes a request — a `role`,
`resource`, and `action` (all atoms) — and a list of statement maps. It must
decide the request's effect as follows:

1. First, select every statement in `policies` that **matches** the request.
   Use the private helper `matches?/4` to test whether a statement matches the
   given `role`, `resource`, and `action`.
2. If **any** matching statement has effect `:deny`, return `:deny`.
3. Otherwise, if **any** matching statement has effect `:allow`, return `:allow`.
4. Otherwise (no statement matched at all), return `:deny` (default deny).

Use the private helper `effect_of/1` to read a statement's effect (which
defaults to `:allow` when the `:effect` key is absent). Explicit deny must win
over allow independent of list order, so you cannot short-circuit on the first
match — you must consider all matching statements before deciding. The function
head already guards on `is_list(policies)`.

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
    # TODO
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