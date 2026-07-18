# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `Rbac` that resolves permissions for a **principal that can hold multiple roles at once**, using **`"resource:action"` permission strings with wildcard patterns**.

Roles are defined as a map from a role atom to a list of permission-pattern strings:

```elixir
%{
  viewer: ["posts:read", "comments:read"],
  editor: ["posts:read", "posts:write", "comments:read", "comments:write"],
  admin:  ["*:*"]
}
```

A permission pattern is a colon-separated string of two segments, `"<resource>:<action>"`, where either segment may be the literal `"*"` wildcard which matches any value in that position. Examples: `"posts:read"`, `"posts:*"`, `"*:read"`, `"*:*"`.

A **principal** is either:

- a plain list of role atoms, e.g. `[:viewer, :editor]`, or
- a map `%{roles: [atom], grants: [String.t()]}` where `:grants` is a list of extra permission-pattern strings granted directly to that principal (in addition to those from its roles). Missing `:roles` / `:grants` keys default to `[]`.

A principal's effective permissions are the **union** of the patterns from every role it holds plus its direct grants.

I need the following public API:

- `Rbac.effective_permissions(principal, role_defs)` — returns a `MapSet` of the principal's effective permission-pattern strings (deduplicated by the set). An empty principal, or one holding only unknown roles, yields `MapSet.new()`.
- `Rbac.permitted?(principal, resource, action, role_defs)` — takes `resource` and `action` as atoms, builds the target `"resource:action"`, and returns `true` if **any** effective pattern matches the target, else `false`. Matching is segment-by-segment after splitting both pattern and target on `":"`, where `"*"` matches any value in its position. A pattern matches only when it has the **same number of segments** as the two-segment target: a pattern with a different segment count (e.g. a bare `"posts"`, or a three-segment `"posts:read:extra"` / `"*:*:*"`) never matches. Unknown roles contribute no permissions rather than raising.

Give me the complete module in a single file with no external dependencies.

## The buggy module

```elixir
defmodule Rbac do
  @moduledoc """
  Multi-role RBAC with wildcard `"resource:action"` permission patterns.

  A principal may hold several roles simultaneously; its effective permission
  set is the union of every held role's patterns plus any direct grants.
  Authorization matches a `"resource:action"` target against each pattern
  segment-by-segment, where the literal `"*"` matches any value in that
  position.

  ## Role definitions

      %{role_atom => ["resource:action", "resource:*", "*:action", "*:*"]}

  ## Principal

    * a list of role atoms — `[:viewer, :editor]`, or
    * a map — `%{roles: [atom], grants: [String.t()]}` (missing keys default
      to `[]`).
  """

  @type principal :: [atom()] | %{optional(:roles) => [atom()], optional(:grants) => [String.t()]}
  @type role_defs :: %{optional(atom()) => [String.t()]}

  @doc """
  Returns the `MapSet` of effective permission patterns for `principal`.

  Unknown roles contribute no permissions.
  """
  @spec effective_permissions(principal(), role_defs()) :: MapSet.t()
  def effective_permissions(principal, role_defs) do
    %{roles: roles, grants: grants} = normalize(principal)

    from_roles = Enum.flat_map(roles, fn role -> Map.get(role_defs, role, []) end)

    MapSet.new(from_roles ++ grants)
  end

  @doc """
  Returns `true` when any effective pattern matches `"resource:action"`.
  """
  @spec permitted?(principal(), atom(), atom(), role_defs()) :: boolean()
  def permitted?(principal, resource, action, role_defs) do
    target = "#{resource}:#{action}"
    target_segments = String.split(target, ":")

    principal
    |> effective_permissions(role_defs)
    |> Enum.any?(fn pattern -> pattern_match?(pattern, target_segments) end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize(principal) when is_list(principal), do: %{roles: principal, grants: []}

  defp normalize(principal) when is_map(principal) do
    %{roles: Map.get(principal, :roles, []), grants: Map.get(principal, :grants, [])}
  end

  defp pattern_match?(pattern, target_segments) do
    segments_match?(String.split(pattern, ":"), target_segments)
  end

  defp segments_match?([p | ps], [t | ts]) do
    (p == "*" or p == t) and segments_match?(ps, ts)
  end

  defp segments_match?([], []), do: false
  defp segments_match?(_, _), do: false
end
```

## Failing test report

```
8 of 13 test(s) failed:

  * test single role viewer can read posts but not write
      
      
      Expected truthy, got false
      code: assert Rbac.permitted?([:viewer], :posts, :read, @roles)
      arguments:
      
               # 1
               [:viewer]
      
               # 2
               :posts
      
               # 3
               :read
      
               # 4
               %{editor: ["posts:read", "posts:write", "comments:read", "comments:write"], viewer: ["posts:read", "comments:read"], moderator: ["comments:*"], admin: ["*:*"]}
      
      

  * test single role editor can write posts
      
      
      Expected truthy, got false
      code: assert Rbac.permitted?([:editor], :posts, :write, @roles)
      arguments:
      
               # 1
               [:editor]
      
               # 2
               :posts
      
               # 3
               :write
      
               # 4
               %{editor: ["posts:read", "posts:write", "comments:read", "comments:write"], viewer: ["posts:read", "comments:read"], moderator: ["comments:*"], admin: ["*:*"]}
      
      

  * test multiple roles union combines permissions of all held roles
      
      
      Expected truthy, got false
      code: assert Rbac.permitted?(principal, :posts, :read, @roles)
      arguments:
      
               # 1
               [:viewer, :moderator]
      
               # 2
               :posts
      
               # 3
               :read
      
               # 4
               %{editor: ["posts:read", "posts:write", "comments:read", "comments:write"], viewer: ["posts:read", "comments:read"], moderator: ["comments:*"], admin: ["*:*"]}
      
      

  * test wildcard patterns admin *:* matches everything
      
      
      Expected truthy, got false
      code: assert Rbac.permitted?([:admin], :posts, :read, @roles)
      arguments:
      
               # 1
               [:admin]
      
               # 2
               :posts
      
               # 3
               :read
      
               # 4
               %{editor: ["posts:read", "posts:write", "comments:read", "comments:write"], viewer: ["posts:read", "comments:read"], moderator: ["comments:*"], admin: ["*:*"]}
      
      

  (…4 more)
```
