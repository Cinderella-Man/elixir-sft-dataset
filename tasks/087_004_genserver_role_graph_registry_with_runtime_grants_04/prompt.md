# Task: Implement `handle_call/3` for `RoleRegistry`

`RoleRegistry` is a `GenServer` that maintains a mutable role-inheritance DAG
with runtime grant/revoke of permissions. The server state is a map:

```elixir
%{
  roles: MapSet.t(role),
  inherits: %{role => MapSet.t(parent_role)},
  grants: %{role => MapSet.t({resource, action})}
}
```

All of the client API functions dispatch to `GenServer.call/2`, so every request
is handled by `handle_call/3`. The client API, the `init/1` callback, and the
private graph helpers (`reachable?/3`, `do_reach/4`, `closure/2`,
`build_closure/3`) are already written for you. Implement the `handle_call/3`
callback so that it handles each of the following messages, always replying with
the appropriate value and returning the (possibly updated) state:

- **`{:add_role, role}`** — Add `role` to `state.roles`. Idempotent. Reply `:ok`.

- **`{:add_inheritance, child, parent}`** — Record that `child` inherits
  `parent`. If either `child` or `parent` is not in `state.roles`, reply
  `{:error, :unknown_role}` and leave state unchanged. If the edge would create
  a cycle — either a self-edge (`child == parent`) or because `parent` can
  already reach `child` through existing inheritance edges (use `reachable?/3`) —
  reply `{:error, :cycle}` and leave state unchanged. Otherwise add `parent` to
  the set of `child`'s parents in `state.inherits` and reply `:ok`.

- **`{:grant, role, resource, action}`** — If `role` exists, add
  `{resource, action}` to that role's grant set in `state.grants` and reply
  `:ok` (idempotent). If `role` does not exist, reply `{:error, :unknown_role}`
  and leave state unchanged.

- **`{:revoke, role, resource, action}`** — Remove `{resource, action}` from
  `role`'s own grant set in `state.grants` (only that role's direct grant).
  Reply `:ok` even if the grant was not present.

- **`{:can?, role, resource, action}`** — Reply `true` if `role`, or any role it
  inherits transitively, has a direct grant for `{resource, action}`; otherwise
  reply `false`. Reply `false` for an unknown role. Compute the set of roles to
  check with `closure/2` and look each one up in `state.grants`.

Below is the complete module with the body of `handle_call/3` replaced by
`# TODO`. Implement it.

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
  def handle_call(request, from, state) do
    # TODO
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