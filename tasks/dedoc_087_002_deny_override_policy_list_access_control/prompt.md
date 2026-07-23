# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule AccessPolicy do
  def evaluate(role, resource, action, policies) when is_list(policies) do
    matching = Enum.filter(policies, &matches?(&1, role, resource, action))

    cond do
      Enum.any?(matching, &(effect_of(&1) == :deny)) -> :deny
      Enum.any?(matching, &(effect_of(&1) == :allow)) -> :allow
      true -> :deny
    end
  end

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
