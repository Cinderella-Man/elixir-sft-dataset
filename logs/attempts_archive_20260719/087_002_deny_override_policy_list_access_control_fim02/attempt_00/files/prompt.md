Implement the private `field_match?/2` function. It decides whether a single
statement field (the expected value taken from a policy statement's `:roles`,
`:resource`, or `:action` key) matches a concrete request value.

It takes the expected field specification as its first argument and the request
value as its second argument, and must handle three cases:

- When the expected value is the atom `:any`, it matches any request value and
  returns `true`.
- When the expected value is a list, it matches when the request value is a
  member of that list.
- Otherwise (the expected value is a single atom), it matches only when the
  expected value is equal to the request value.

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

  defp field_match?(expected, value) do
    # TODO
  end
end
```