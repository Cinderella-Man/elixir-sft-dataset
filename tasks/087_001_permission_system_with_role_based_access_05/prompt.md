# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `fetch_action`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design brief: role-based access control with owner overrides

## Problem

An application needs to decide, for a given user role, whether an action on a resource is allowed. Roles are hierarchical, so authorization checks should not have to enumerate every role that can perform an action — a more privileged role should satisfy a rule written for a less privileged one. Separately, some actions are not role-gated at all but ownership-gated: the acting user may perform them only on records they own, whatever their role. Both mechanisms have to coexist inside the same rule set.

## Constraints

- Deliver an Elixir module called `Permissions` implementing a role-based access control system with hierarchical roles and owner-based overrides.
- The role hierarchy, from least to most privileged, is: `:viewer < :editor < :manager < :admin`. A user with a higher role automatically inherits all permissions of lower roles.
- Permissions are defined as a map of the shape `%{resource => %{action => required_role}}`, for example:

```elixir
%{
  posts: %{read: :viewer, create: :editor, update: :editor, delete: :manager},
  settings: %{read: :manager, update: :admin}
}
```

- Ship the complete module in a single file with no external dependencies.

## Required interface

1. `Permissions.can?(role, resource, action, rules)` — returns `true` if the given role is at or above the role required by `rules` for `resource` + `action`, and `false` otherwise. Return `false` for unknown resources or actions rather than raising.
2. `Permissions.can?(role, resource, action, rules, opts)` — same as above but accepts an `opts` keyword list. When `opts` includes `[owner_id: id, user_id: id]` and the resource+action rule is the atom `:owner`, grant access if and only if `owner_id == user_id`, regardless of role. If the rule is `:owner` but no `opts` are provided (or the ids don't match), deny access.

## Acceptance criteria

- Role inheritance holds across the hierarchy: the `:admin` role must be able to do everything that any lower role can do.
- Unknown resources and unknown actions produce `false`, never an exception.
- The `:owner` special-case is composable — a resource action can require `:owner` while other actions on the same resource require normal roles.
- Both public functions are present and behave as specified above.

## The module with `fetch_action` missing

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

  defp fetch_action(action_rules, action) do
    # TODO
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

Output only `fetch_action` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
