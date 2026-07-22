defmodule RoleRegistryTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, server} = RoleRegistry.start_link()
    %{server: server}
  end

  describe "roles and direct grants" do
    test "grant then can?", %{server: s} do
      assert RoleRegistry.add_role(s, :editor) == :ok
      assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
      assert RoleRegistry.can?(s, :editor, :posts, :write)
      refute RoleRegistry.can?(s, :editor, :posts, :delete)
    end

    test "unknown role can?/grant", %{server: s} do
      refute RoleRegistry.can?(s, :ghost, :posts, :read)
      assert RoleRegistry.grant(s, :ghost, :posts, :read) == {:error, :unknown_role}
    end

    test "add_role is idempotent", %{server: s} do
      assert RoleRegistry.add_role(s, :viewer) == :ok
      assert RoleRegistry.add_role(s, :viewer) == :ok
    end

    test "revoke removes only that grant", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :editor, :posts, :write)
      RoleRegistry.grant(s, :editor, :posts, :read)
      assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
      refute RoleRegistry.can?(s, :editor, :posts, :write)
      assert RoleRegistry.can?(s, :editor, :posts, :read)
    end

    test "revoke of missing grant is ok", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
    end
  end

  describe "inheritance" do
    test "child inherits parent permissions", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      assert RoleRegistry.add_inheritance(s, :editor, :viewer) == :ok

      assert RoleRegistry.can?(s, :editor, :posts, :read)
      refute RoleRegistry.can?(s, :viewer, :posts, :write)
    end

    test "transitive inheritance across a chain", %{server: s} do
      for r <- [:viewer, :editor, :manager], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      RoleRegistry.grant(s, :editor, :posts, :write)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      RoleRegistry.add_inheritance(s, :manager, :editor)

      assert RoleRegistry.can?(s, :manager, :posts, :read)
      assert RoleRegistry.can?(s, :manager, :posts, :write)
    end

    test "diamond inheritance (multiple parents)", %{server: s} do
      for r <- [:base, :left, :right, :top], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :left, :a, :x)
      RoleRegistry.grant(s, :right, :b, :y)
      RoleRegistry.add_inheritance(s, :top, :left)
      RoleRegistry.add_inheritance(s, :top, :right)

      assert RoleRegistry.can?(s, :top, :a, :x)
      assert RoleRegistry.can?(s, :top, :b, :y)
    end

    test "unknown roles rejected", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      assert RoleRegistry.add_inheritance(s, :editor, :nope) == {:error, :unknown_role}
      assert RoleRegistry.add_inheritance(s, :nope, :editor) == {:error, :unknown_role}
    end
  end

  describe "cycle detection" do
    test "self edge rejected", %{server: s} do
      RoleRegistry.add_role(s, :a)
      assert RoleRegistry.add_inheritance(s, :a, :a) == {:error, :cycle}
    end

    test "direct back-edge rejected", %{server: s} do
      RoleRegistry.add_role(s, :a)
      RoleRegistry.add_role(s, :b)
      assert RoleRegistry.add_inheritance(s, :a, :b) == :ok
      assert RoleRegistry.add_inheritance(s, :b, :a) == {:error, :cycle}
    end

    test "transitive cycle rejected and state unchanged", %{server: s} do
      for r <- [:a, :b, :c], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :a, :res, :act)
      RoleRegistry.add_inheritance(s, :b, :a)
      RoleRegistry.add_inheritance(s, :c, :b)
      # c -> b -> a already; adding a -> c would close a cycle
      assert RoleRegistry.add_inheritance(s, :a, :c) == {:error, :cycle}
      # state unchanged: c still inherits a's grant
      assert RoleRegistry.can?(s, :c, :res, :act)
    end
  end

  describe "runtime mutation affects inherited permissions" do
    test "revoking parent grant affects child immediately", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      assert RoleRegistry.can?(s, :editor, :posts, :read)

      RoleRegistry.revoke(s, :viewer, :posts, :read)
      refute RoleRegistry.can?(s, :editor, :posts, :read)
    end

    test "granting parent later flows to child", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      refute RoleRegistry.can?(s, :editor, :settings, :read)

      RoleRegistry.grant(s, :viewer, :settings, :read)
      assert RoleRegistry.can?(s, :editor, :settings, :read)
    end
  end
end