# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

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
