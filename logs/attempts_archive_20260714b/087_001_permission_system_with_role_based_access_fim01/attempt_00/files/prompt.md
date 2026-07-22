# Fill in the Middle: `Permissions.can?/5`

The module below implements a role-based access control system with hierarchical
roles and owner-based overrides. Every function is complete **except** the
5-arity `can?/5`, whose body has been replaced with `# TODO`.

## Your Task

Implement the public `can?/5` function. It takes `role`, `resource`, `action`,
`rules`, and an `opts` keyword list, and returns a `boolean()`.

It should look up the rule for the requested `{resource, action}` pair inside the
`rules` map and decide whether access is granted:

1. First resolve the action-rule map for `resource`. Use the private helper
   `fetch_resource/2`, which returns `{:ok, action_rules}` when the resource
   exists (and maps to a map) and `:error` otherwise.
2. Then resolve the rule for `action` within that map. Use the private helper
   `fetch_action/2`, which returns `{:ok, rule}` or `:error`.
3. Once both lookups succeed, delegate the actual decision to the private
   `check/3` helper, calling it as `check(rule, role, opts)`. `check/3` already
   handles the `:owner` identity check, normal role-rank comparison, and the
   deny-by-default case.
4. If either lookup fails (unknown resource or unknown action), return `false`
   rather than raising.

Use a `with` expression to chain the two lookups, and its `else` clause to map
the `:error` case to `false`. Do not re-implement the logic already provided by
`fetch_resource/2`, `fetch_action/2`, or `check/3`.

## Module

```elixir
defmodule Permissions do
  @moduledoc """
  Role-based access control with hierarchical roles and owner-based overrides.

  ## Role Hierarchy (least → most privileged)

      :viewer < :editor < :manager < :admin

  ## Rules Map Shape

      %{
        resource => %{
          action => required_role | :owner
        }
      }

  ## Owner Override

  When a rule is set to `:owner`, access is granted if and only if the
  `owner_id` and `user_id` supplied in `opts` are equal (and non-nil).
  The caller's role is irrelevant for `:owner`-gated actions.
  """

  # ---------------------------------------------------------------------------
  # Role hierarchy
  # ---------------------------------------------------------------------------

  @role_rank %{viewer: 0, editor: 1, manager: 2, admin: 3}

  @roles Map.keys(@role_rank)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns `true` when `role` satisfies the rule for `{resource, action}` in
  `rules`, `false` otherwise (including unknown resources / actions).

  Equivalent to `can?(role, resource, action, rules, [])`.
  """
  @spec can?(atom(), atom(), atom(), map()) :: boolean()
  def can?(role, resource, action, rules) do
    can?(role, resource, action, rules, [])
  end

  @doc """
  Same as `can?/4` but accepts an `opts` keyword list.

  ## Options

  * `:owner_id` – the ID of whoever owns the resource.
  * `:user_id`  – the ID of the user requesting access.

  When the rule for `{resource, action}` is the atom `:owner`, access is
  granted if and only if `owner_id == user_id` (both must be present and
  equal). The caller's role plays no part in this decision.

  For all other rule values the options are ignored and normal role
  comparison applies.
  """
  @spec can?(atom(), atom(), atom(), map(), keyword()) :: boolean()
  def can?(role, resource, action, rules, opts) do
    # TODO
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