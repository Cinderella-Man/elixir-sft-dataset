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
      perms = Rbac.effective_permissions([:viewer, :editor], @roles)
      assert MapSet.member?(perms, "posts:write")
      assert MapSet.member?(perms, "comments:read")
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

  test "map principal with only :grants key defaults roles to empty and honors grants" do
    principal = %{grants: ["reports:export"]}
    assert Rbac.permitted?(principal, :reports, :export, @roles)
    refute Rbac.permitted?(principal, :posts, :read, @roles)
    assert Rbac.effective_permissions(principal, @roles) == MapSet.new(["reports:export"])
  end

  test "overlapping role patterns are unioned without duplicates" do
    assert Rbac.effective_permissions([:viewer, :editor], @roles) ==
             MapSet.new([
               "posts:read",
               "posts:write",
               "comments:read",
               "comments:write"
             ])
  end

  test "effective_permissions of roles plus grants is exactly the merged set" do
    principal = %{roles: [:moderator], grants: ["comments:*", "billing:refund"]}

    assert Rbac.effective_permissions(principal, @roles) ==
             MapSet.new(["comments:*", "billing:refund"])
  end

  test "unknown role alongside a known role keeps the known role's permissions" do
    principal = [:viewer, :ghost]

    assert Rbac.effective_permissions(principal, @roles) ==
             MapSet.new(["posts:read", "comments:read"])

    assert Rbac.permitted?(principal, :posts, :read, @roles)
    refute Rbac.permitted?(principal, :posts, :write, @roles)
  end

  test "pattern with more than two segments never matches a two-segment target" do
    roles = %{odd: ["posts:read:extra", "*:*:*"]}
    refute Rbac.permitted?([:odd], :posts, :read, roles)
    refute Rbac.permitted?([:odd], :anything, :whatever, roles)
  end

  test "empty role list principal is denied everything" do
    assert Rbac.effective_permissions([], @roles) == MapSet.new()
    refute Rbac.permitted?([], :posts, :read, @roles)
    refute Rbac.permitted?(%{roles: [], grants: []}, :posts, :read, @roles)
  end
end
