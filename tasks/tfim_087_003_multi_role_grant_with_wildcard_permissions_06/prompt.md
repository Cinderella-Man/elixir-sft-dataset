# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp segments_match?([], []), do: true
  defp segments_match?(_, _), do: false
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RbacTest do
  use ExUnit.Case, async: false

  @roles %{
    viewer: ["posts:read", "comments:read"],
    editor: ["posts:read", "posts:write", "comments:read", "comments:write"],
    moderator: ["comments:*"],
    admin: ["*:*"]
  }

  describe "single role" do
    test "viewer can read posts but not write" do
      assert Rbac.permitted?([:viewer], :posts, :read, @roles)
      refute Rbac.permitted?([:viewer], :posts, :write, @roles)
    end

    test "editor can write posts" do
      assert Rbac.permitted?([:editor], :posts, :write, @roles)
    end

    test "unknown role grants nothing" do
      refute Rbac.permitted?([:ghost], :posts, :read, @roles)
      assert Rbac.effective_permissions([:ghost], @roles) == MapSet.new()
    end
  end

  describe "multiple roles union" do
    test "combines permissions of all held roles" do
      principal = [:viewer, :moderator]
      assert Rbac.permitted?(principal, :posts, :read, @roles)
      assert Rbac.permitted?(principal, :comments, :delete, @roles)
      refute Rbac.permitted?(principal, :posts, :write, @roles)
    end

    test "effective_permissions is the union set" do
      # TODO
    end
  end

  describe "wildcard patterns" do
    test "admin *:* matches everything" do
      assert Rbac.permitted?([:admin], :posts, :read, @roles)
      assert Rbac.permitted?([:admin], :settings, :destroy, @roles)
      assert Rbac.permitted?([:admin], :anything, :whatever, @roles)
    end

    test "resource wildcard (comments:*)" do
      assert Rbac.permitted?([:moderator], :comments, :read, @roles)
      assert Rbac.permitted?([:moderator], :comments, :ban, @roles)
      refute Rbac.permitted?([:moderator], :posts, :read, @roles)
    end

    test "action wildcard (*:read)" do
      roles = %{auditor: ["*:read"]}
      assert Rbac.permitted?([:auditor], :posts, :read, roles)
      assert Rbac.permitted?([:auditor], :settings, :read, roles)
      refute Rbac.permitted?([:auditor], :posts, :write, roles)
    end

    test "single-segment pattern does not match two-segment target" do
      roles = %{weird: ["posts"]}
      refute Rbac.permitted?([:weird], :posts, :read, roles)
    end
  end

  describe "principal as map with direct grants" do
    test "grants add to role permissions" do
      principal = %{roles: [:viewer], grants: ["reports:export"]}
      assert Rbac.permitted?(principal, :posts, :read, @roles)
      assert Rbac.permitted?(principal, :reports, :export, @roles)
      refute Rbac.permitted?(principal, :posts, :write, @roles)
    end

    test "grants may themselves be wildcards" do
      principal = %{roles: [], grants: ["billing:*"]}
      assert Rbac.permitted?(principal, :billing, :refund, @roles)
      refute Rbac.permitted?(principal, :posts, :read, @roles)
    end

    test "missing keys default to empty" do
      assert Rbac.effective_permissions(%{}, @roles) == MapSet.new()

      assert Rbac.effective_permissions(%{roles: [:viewer]}, @roles)
             |> MapSet.member?("posts:read")
    end
  end

  describe "deny by default" do
    test "no matching pattern returns false" do
      refute Rbac.permitted?([:viewer], :settings, :update, @roles)
    end
  end
end
```
