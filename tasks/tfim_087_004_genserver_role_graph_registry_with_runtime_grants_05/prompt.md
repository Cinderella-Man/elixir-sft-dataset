# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RoleRegistry do
  @moduledoc """
  A GenServer maintaining a mutable role-inheritance DAG with runtime
  grant/revoke of permissions.

  Roles form an arbitrary acyclic inheritance graph: if `child` inherits
  `parent`, then `child` holds every permission `parent` holds, transitively.
  Adding an edge that would introduce a cycle is rejected, leaving state
  untouched. Grants and revokes take effect immediately for all inheriting
  roles because `can?/4` resolves the inheritance closure at query time.

  ## State

      %{
        roles:    MapSet.t(role),
        inherits: %{role => MapSet.t(parent_role)},
        grants:   %{role => MapSet.t({resource, action})}
      }
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `RoleRegistry` GenServer.

  Standard `GenServer` options such as `:name` are honored. The initial state
  has no roles, no inheritance edges, and no grants.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Registers `role`. Idempotent — adding an existing role is a no-op. Returns `:ok`.
  """
  @spec add_role(GenServer.server(), atom()) :: :ok
  def add_role(server, role), do: GenServer.call(server, {:add_role, role})

  @doc """
  Records that `child` inherits `parent`'s permissions transitively.

  Both roles must already exist, otherwise returns `{:error, :unknown_role}`.
  An edge that would create a cycle (including a self-edge) is rejected with
  `{:error, :cycle}`, leaving state unchanged. On success returns `:ok`.
  """
  @spec add_inheritance(GenServer.server(), atom(), atom()) ::
          :ok | {:error, :unknown_role | :cycle}
  def add_inheritance(server, child, parent) do
    GenServer.call(server, {:add_inheritance, child, parent})
  end

  @doc """
  Grants permission for `{resource, action}` directly to `role`.

  The role must exist, otherwise returns `{:error, :unknown_role}`. Idempotent.
  Returns `:ok` on success.
  """
  @spec grant(GenServer.server(), atom(), atom(), atom()) :: :ok | {:error, :unknown_role}
  def grant(server, role, resource, action) do
    GenServer.call(server, {:grant, role, resource, action})
  end

  @doc """
  Removes a direct `{resource, action}` grant from `role`.

  Only the role's own grant is removed, not inherited ones. Returns `:ok` even
  if the grant was not present.
  """
  @spec revoke(GenServer.server(), atom(), atom(), atom()) :: :ok
  def revoke(server, role, resource, action) do
    GenServer.call(server, {:revoke, role, resource, action})
  end

  @doc """
  Returns `true` if `role`, or any role it inherits transitively, has a direct
  grant for `{resource, action}`; otherwise `false`.

  Returns `false` for an unknown role.
  """
  @spec can?(GenServer.server(), atom(), atom(), atom()) :: boolean()
  def can?(server, role, resource, action) do
    GenServer.call(server, {:can?, role, resource, action})
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    {:ok, %{roles: MapSet.new(), inherits: %{}, grants: %{}}}
  end

  @impl true
  def handle_call({:add_role, role}, _from, state) do
    {:reply, :ok, %{state | roles: MapSet.put(state.roles, role)}}
  end

  def handle_call({:add_inheritance, child, parent}, _from, state) do
    cond do
      not MapSet.member?(state.roles, child) ->
        {:reply, {:error, :unknown_role}, state}

      not MapSet.member?(state.roles, parent) ->
        {:reply, {:error, :unknown_role}, state}

      child == parent ->
        {:reply, {:error, :cycle}, state}

      # If `parent` already reaches `child` via inheritance, then `child` is an
      # ancestor of `parent`; adding child -> parent would close a cycle.
      reachable?(state.inherits, parent, child) ->
        {:reply, {:error, :cycle}, state}

      true ->
        parents = state.inherits |> Map.get(child, MapSet.new()) |> MapSet.put(parent)
        {:reply, :ok, %{state | inherits: Map.put(state.inherits, child, parents)}}
    end
  end

  def handle_call({:grant, role, resource, action}, _from, state) do
    if MapSet.member?(state.roles, role) do
      key = {resource, action}
      set = state.grants |> Map.get(role, MapSet.new()) |> MapSet.put(key)
      {:reply, :ok, %{state | grants: Map.put(state.grants, role, set)}}
    else
      {:reply, {:error, :unknown_role}, state}
    end
  end

  def handle_call({:revoke, role, resource, action}, _from, state) do
    key = {resource, action}
    set = state.grants |> Map.get(role, MapSet.new()) |> MapSet.delete(key)
    {:reply, :ok, %{state | grants: Map.put(state.grants, role, set)}}
  end

  def handle_call({:can?, role, resource, action}, _from, state) do
    result =
      if MapSet.member?(state.roles, role) do
        key = {resource, action}

        state.inherits
        |> closure(role)
        |> Enum.any?(fn r ->
          MapSet.member?(Map.get(state.grants, r, MapSet.new()), key)
        end)
      else
        false
      end

    {:reply, result, state}
  end

  # ---------------------------------------------------------------------------
  # Graph helpers
  # ---------------------------------------------------------------------------

  # Can we reach `target` from `from` following inheritance edges?
  defp reachable?(inherits, from, target) do
    do_reach(inherits, [from], MapSet.new(), target)
  end

  defp do_reach(_inherits, [], _seen, _target), do: false

  defp do_reach(inherits, [node | rest], seen, target) do
    cond do
      node == target ->
        true

      MapSet.member?(seen, node) ->
        do_reach(inherits, rest, seen, target)

      true ->
        parents = inherits |> Map.get(node, MapSet.new()) |> MapSet.to_list()
        do_reach(inherits, parents ++ rest, MapSet.put(seen, node), target)
    end
  end

  # The set containing `role` and every role reachable via inheritance edges.
  defp closure(inherits, role) do
    build_closure(inherits, [role], MapSet.new())
  end

  defp build_closure(_inherits, [], acc), do: acc

  defp build_closure(inherits, [node | rest], acc) do
    if MapSet.member?(acc, node) do
      build_closure(inherits, rest, acc)
    else
      parents = inherits |> Map.get(node, MapSet.new()) |> MapSet.to_list()
      build_closure(inherits, parents ++ rest, MapSet.put(acc, node))
    end
  end
end
```

## Test harness — implement the `# TODO` test

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
      # TODO
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
