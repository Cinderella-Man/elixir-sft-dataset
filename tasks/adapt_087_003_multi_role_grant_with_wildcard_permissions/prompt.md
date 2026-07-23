# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

## New specification

**Ticket:** Implement `Rbac` — permission resolution for a principal that may hold multiple roles at once, over `"resource:action"` permission strings with wildcard patterns.

**Deliverable**
- Complete Elixir module named `Rbac`, single file, no external dependencies.

**Role definitions**
- Roles are a map from a role atom to a list of permission-pattern strings.
- Shape:

```elixir
%{
  viewer: ["posts:read", "comments:read"],
  editor: ["posts:read", "posts:write", "comments:read", "comments:write"],
  admin:  ["*:*"]
}
```

**Permission patterns**
- A pattern is a colon-separated string of two segments, `"<resource>:<action>"`.
- Either segment may be the literal `"*"` wildcard, which matches any value in that position.
- Examples: `"posts:read"`, `"posts:*"`, `"*:read"`, `"*:*"`.

**Principal shapes**
- A plain list of role atoms, e.g. `[:viewer, :editor]`; or
- a map `%{roles: [atom], grants: [String.t()]}`, where `:grants` is a list of extra permission-pattern strings granted directly to that principal, in addition to those from its roles.
- Missing `:roles` / `:grants` keys default to `[]`.
- Effective permissions = the **union** of the patterns from every role held plus the direct grants.

**API — `Rbac.effective_permissions(principal, role_defs)`**
- Returns a `MapSet` of the principal's effective permission-pattern strings (deduplicated by the set).
- An empty principal, or one holding only unknown roles, yields `MapSet.new()`.

**API — `Rbac.permitted?(principal, resource, action, role_defs)`**
- `resource` and `action` arrive as atoms; build the target `"resource:action"` from them.
- Returns `true` if **any** effective pattern matches the target, else `false`.
- Match segment-by-segment after splitting both pattern and target on `":"`; `"*"` matches any value in its position.
- A pattern matches only when it has the **same number of segments** as the two-segment target. A pattern with a different segment count — e.g. a bare `"posts"`, or a three-segment `"posts:read:extra"` / `"*:*:*"` — never matches.
- Unknown roles contribute no permissions rather than raising.
