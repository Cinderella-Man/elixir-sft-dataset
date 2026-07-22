# Task: Implement `check/3`

Complete the `Permissions` module below by implementing the private `check/3`
function. Every other function in the module is already written and must be left
exactly as-is — implement only `check/3`.

## What `check/3` must do

`check/3` is the private decision function invoked once a rule has been located
for a given `{resource, action}` pair. It receives three arguments:

1. `rule` — the value found in the rules map for the resource+action. This is
   either the atom `:owner` or a required-role atom (e.g. `:viewer`, `:editor`,
   `:manager`, `:admin`).
2. `role` — the caller's role.
3. `opts` — the keyword list passed through from `can?/5` (may contain
   `:owner_id` and `:user_id`).

It must return a `boolean()` according to these rules:

- **Owner override.** When `rule` is the atom `:owner`, the caller's role is
  irrelevant. Read `owner_id` and `user_id` from `opts` and grant access
  (`true`) if and only if both are present (non-nil) and equal. Otherwise return
  `false`.
- **Normal role comparison.** When `rule` is a known role and `role` is also a
  known role, ignore `opts` and grant access if and only if the caller's role
  rank is greater than or equal to the required role's rank. Use the existing
  `rank/1` helper for the comparison.
- **Anything else.** For an unknown `rule` value or an unknown caller `role`,
  deny access by returning `false`.

Implement this using multiple `defp check/3` clauses with appropriate pattern
matching and guards; the module already defines `@roles` and `@role_rank` for
you to use.

## Module skeleton

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

  # Retrieve the rule for a single action, returning :error when absent.
  defp fetch_action(action_rules, action) do
    Map.fetch(action_rules, action)
  end

  # Decide whether `rule` is satisfied by `role`/`opts`.
  defp check(rule, role, opts) do
    # TODO
  end

  defp rank(role), do: Map.fetch!(@role_rank, role)
end
```