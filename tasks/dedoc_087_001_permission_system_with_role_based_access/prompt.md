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
defmodule Permissions do
  # ---------------------------------------------------------------------------
  # Role hierarchy
  # ---------------------------------------------------------------------------

  @role_rank %{viewer: 0, editor: 1, manager: 2, admin: 3}

  @roles Map.keys(@role_rank)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def can?(role, resource, action, rules) do
    can?(role, resource, action, rules, [])
  end

  def can?(role, resource, action, rules, opts) do
    with {:ok, action_rules} <- fetch_resource(rules, resource),
         {:ok, rule} <- fetch_action(action_rules, action) do
      check(rule, role, opts)
    else
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Retrieve the action-rule map for a resource, returning :error when absent.
  defp fetch_resource(rules, resource) do
    case Map.fetch(rules, resource) do
      {:ok, action_rules} when is_map(action_rules) -> {:ok, action_rules}
      _ -> :error
    end
  end

  # Retrieve the rule for a single action, returning :error when absent.
  defp fetch_action(action_rules, action) do
    Map.fetch(action_rules, action)
  end

  # `:owner` rule — identity check only, role is irrelevant.
  defp check(:owner, _role, opts) do
    owner_id = Keyword.get(opts, :owner_id)
    user_id = Keyword.get(opts, :user_id)

    not is_nil(owner_id) and not is_nil(user_id) and owner_id == user_id
  end

  # Normal role rule — compare ranks, ignore opts.
  defp check(required_role, role, _opts)
       when required_role in @roles and role in @roles do
    rank(role) >= rank(required_role)
  end

  # Unknown role or required_role value — deny.
  defp check(_required_role, _role, _opts), do: false

  defp rank(role), do: Map.fetch!(@role_rank, role)
end
```
