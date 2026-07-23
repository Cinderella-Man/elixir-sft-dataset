# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Write me an Elixir module called `Permissions` that implements a role-based access control system with hierarchical roles and owner-based overrides.

The role hierarchy, from least to most privileged, is: `:viewer < :editor < :manager < :admin`. A user with a higher role automatically inherits all permissions of lower roles.

Permissions are defined as a map of the shape `%{resource => %{action => required_role}}`, for example:
```elixir
%{
  posts: %{read: :viewer, create: :editor, update: :editor, delete: :manager},
  settings: %{read: :manager, update: :admin}
}
```

I need the following in the public API:

- `Permissions.can?(role, resource, action, rules)` — returns `true` if the given role is at or above the role required by `rules` for `resource` + `action`, and `false` otherwise. Return `false` for unknown resources or actions rather than raising.
- `Permissions.can?(role, resource, action, rules, opts)` — same as above but accepts an `opts` keyword list. When `opts` includes `[owner_id: id, user_id: id]` and the resource+action rule is the atom `:owner`, grant access if and only if `owner_id == user_id`, regardless of role. If the rule is `:owner` but no `opts` are provided (or the ids don't match), deny access.

The `:admin` role must be able to do everything that any lower role can do. The `:owner` special-case should be composable — a resource action can require `:owner` while other actions on the same resource require normal roles.

Give me the complete module in a single file with no external dependencies.

## The buggy module

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
    with {:ok, action_rules} <- fetch_resource(rules, resource),
         {:ok, rule} <- fetch_action(action_rules, action) do
      check(rule, role, opts)
    else
      :error -> true
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

## Failing test report

```
2 of 27 test(s) failed:

  * test unknown resource or action returns false for unknown resource
      
      
      Expected false or nil, got true
      code: refute Permissions.can?(:admin, :nonexistent, :read, @rules)
      arguments:
      
               # 1
               :admin
      
               # 2
               :nonexistent
      
               # 3
               :read
      
               # 4
               %{profile: %{update: :owner, read: :viewer}, posts: %{delete: :manager, update: :editor, create: :editor, read: :viewer, publish: :admin}, settings: %{update: :admin, read: :manager}}
      
      

  * test unknown resource or action returns false for unknown action on known resource
      
      
      Expected false or nil, got true
      code: refute Permissions.can?(:admin, :posts, :nonexistent_action, @rules)
      arguments:
      
               # 1
               :admin
      
               # 2
               :posts
      
               # 3
               :nonexistent_action
      
               # 4
               %{profile: %{update: :owner, read: :viewer}, posts: %{delete: :manager, update: :editor, create: :editor, read: :viewer, publish: :admin}, settings: %{update: :admin, read: :manager}}
```
