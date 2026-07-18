# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule RoleRegistry do
  use GenServer

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def add_role(server, role), do: GenServer.call(server, {:add_role, role})

  def add_inheritance(server, child, parent) do
    GenServer.call(server, {:add_inheritance, child, parent})
  end

  def grant(server, role, resource, action) do
    GenServer.call(server, {:grant, role, resource, action})
  end

  def revoke(server, role, resource, action) do
    GenServer.call(server, {:revoke, role, resource, action})
  end

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
