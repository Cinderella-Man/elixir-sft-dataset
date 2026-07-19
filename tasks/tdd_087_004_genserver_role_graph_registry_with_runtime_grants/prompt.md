# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  test "rejected cycle edge is not recorded at all", %{server: s} do
    RoleRegistry.add_role(s, :a)
    RoleRegistry.add_role(s, :b)
    assert RoleRegistry.add_inheritance(s, :a, :b) == :ok
    assert RoleRegistry.add_inheritance(s, :b, :a) == {:error, :cycle}

    RoleRegistry.grant(s, :a, :res, :act)
    # the rejected b -> a edge must not exist, so b must not inherit a's grant
    refute RoleRegistry.can?(s, :b, :res, :act)

    RoleRegistry.grant(s, :b, :other, :act)
    # the accepted a -> b edge must survive the rejection unchanged
    assert RoleRegistry.can?(s, :a, :other, :act)
  end

  test "start_link honors the :name option and the API works by name" do
    name = :role_registry_named_server
    {:ok, _pid} = RoleRegistry.start_link(name: name)

    assert RoleRegistry.add_role(name, :viewer) == :ok
    assert RoleRegistry.add_role(name, :editor) == :ok
    assert RoleRegistry.grant(name, :viewer, :posts, :read) == :ok
    assert RoleRegistry.add_inheritance(name, :editor, :viewer) == :ok
    assert RoleRegistry.can?(name, :editor, :posts, :read)
    refute RoleRegistry.can?(name, :editor, :posts, :write)
  end

  test "fresh server starts with no roles, no edges and no grants" do
    {:ok, s} = RoleRegistry.start_link()

    refute RoleRegistry.can?(s, :editor, :posts, :read)
    assert RoleRegistry.grant(s, :editor, :posts, :read) == {:error, :unknown_role}
    assert RoleRegistry.add_inheritance(s, :editor, :viewer) == {:error, :unknown_role}

    # after adding the roles there must still be no pre-existing edges or grants
    RoleRegistry.add_role(s, :viewer)
    RoleRegistry.add_role(s, :editor)
    RoleRegistry.grant(s, :viewer, :posts, :read)
    refute RoleRegistry.can?(s, :editor, :posts, :read)
  end

  test "granting twice is idempotent so a single revoke clears it", %{server: s} do
    RoleRegistry.add_role(s, :editor)
    assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
    assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
    assert RoleRegistry.can?(s, :editor, :posts, :write)

    assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
    refute RoleRegistry.can?(s, :editor, :posts, :write)
  end

  test "revoking from a child leaves the inherited grant intact", %{server: s} do
    RoleRegistry.add_role(s, :viewer)
    RoleRegistry.add_role(s, :editor)
    RoleRegistry.grant(s, :viewer, :posts, :read)
    RoleRegistry.add_inheritance(s, :editor, :viewer)
    assert RoleRegistry.can?(s, :editor, :posts, :read)

    # editor has no direct grant here; revoking must not touch viewer's grant
    assert RoleRegistry.revoke(s, :editor, :posts, :read) == :ok
    assert RoleRegistry.can?(s, :viewer, :posts, :read)
    assert RoleRegistry.can?(s, :editor, :posts, :read)
  end

  test "revoke on an unknown role returns ok without creating the role", %{server: s} do
    assert RoleRegistry.revoke(s, :ghost, :posts, :read) == :ok
    refute RoleRegistry.can?(s, :ghost, :posts, :read)
    assert RoleRegistry.grant(s, :ghost, :posts, :read) == {:error, :unknown_role}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
