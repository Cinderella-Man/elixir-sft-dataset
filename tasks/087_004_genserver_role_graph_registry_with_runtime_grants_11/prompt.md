# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `init`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# `RoleRegistry` — Runtime-Mutable Role Inheritance Graph

## Overview

This specification describes an Elixir GenServer module named `RoleRegistry` that maintains a **mutable, arbitrary role-inheritance graph** with **runtime grant/revoke of permissions**. The structure is not a fixed four-level ladder; it is a directed acyclic graph of roles that can be reshaped while the server is running.

Inheritance carries the following meaning: if `child` inherits `parent`, then `child` has every permission `parent` has, and everything `parent` inherits, transitively. Revoking a grant from `parent` must immediately affect what `child` can do.

The deliverable is the complete module in a single file with no external dependencies.

## API

The module exposes the public functions below. Each one takes the server `pid` or registered name as its first argument.

- `RoleRegistry.start_link(opts \\ [])` — starts the GenServer. Standard `GenServer` options such as `:name` are honored. Initial state has no roles, no inheritance edges, and no grants.
- `RoleRegistry.add_role(server, role)` — registers a role atom. It returns `:ok`, and it is idempotent: adding an existing role is fine.
- `RoleRegistry.add_inheritance(server, child, parent)` — records that `child` inherits `parent`'s permissions, transitively. Both roles must already exist; otherwise the call returns `{:error, :unknown_role}`. On success it returns `:ok`.
- `RoleRegistry.grant(server, role, resource, action)` — grants permission for `{resource, action}` directly to `role`. The role must exist, otherwise `{:error, :unknown_role}`. It returns `:ok` and is idempotent.
- `RoleRegistry.revoke(server, role, resource, action)` — removes a direct `{resource, action}` grant from `role`, affecting only that role's own grant and not inherited ones. It returns `:ok`.
- `RoleRegistry.can?(server, role, resource, action)` — returns `true` if `role`, or **any role it inherits transitively** (directly, or through a chain of inheritance edges), has a direct grant for `{resource, action}`; otherwise it returns `false`.

## Edge cases

- Adding an inheritance edge that would create a cycle — including a self-edge — must be rejected with `{:error, :cycle}`, and state must be left unchanged.
- `RoleRegistry.add_inheritance(server, child, parent)` with either role not yet registered returns `{:error, :unknown_role}`.
- `RoleRegistry.grant(server, role, resource, action)` for a role that does not exist returns `{:error, :unknown_role}`.
- `RoleRegistry.revoke(server, role, resource, action)` returns `:ok` even if the grant was not present.
- `RoleRegistry.can?(server, role, resource, action)` returns `false` for an unknown role.
- Re-adding an already registered role, and re-granting an already granted `{resource, action}` pair, are both no-ops that still return `:ok`.

## The module with `init` missing

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

  def init(:ok) do
    # TODO
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

Output only `init` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
