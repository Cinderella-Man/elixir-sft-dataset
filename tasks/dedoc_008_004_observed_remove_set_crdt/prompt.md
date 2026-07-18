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
defmodule ORSet do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  def add(server, element, node_id) do
    GenServer.call(server, {:add, element, node_id})
  end

  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: not a current member"
    end
  end

  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  def members(server) do
    GenServer.call(server, :members)
  end

  def merge(server, %{entries: entries, tombstones: tombstones, clock: clock} = _remote)
      when is_map(entries) and is_map(clock) do
    GenServer.call(
      server,
      {:merge, %{entries: entries, tombstones: MapSet.new(tombstones), clock: clock}}
    )
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must have :entries, :tombstones, :clock keys, got: #{inspect(invalid)}"
  end

  def state(server) do
    GenServer.call(server, :state)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, empty_state()}
  end

  @impl GenServer
  def handle_call({:add, element, node_id}, _from, state) do
    # Increment the clock for this node
    new_counter = Map.get(state.clock, node_id, 0) + 1
    new_clock = Map.put(state.clock, node_id, new_counter)
    tag = {node_id, new_counter}

    # Add the tag to the element's entry set
    new_entries =
      Map.update(state.entries, element, MapSet.new([tag]), fn existing ->
        MapSet.put(existing, tag)
      end)

    {:reply, :ok, %{state | entries: new_entries, clock: new_clock}}
  end

  def handle_call({:remove, element}, _from, state) do
    case Map.fetch(state.entries, element) do
      {:ok, tags} when tags != %MapSet{} ->
        if MapSet.size(tags) == 0 do
          {:reply, {:error, :not_a_member}, state}
        else
          # Move all current tags to tombstones
          new_tombstones = MapSet.union(state.tombstones, tags)
          new_entries = Map.delete(state.entries, element)
          {:reply, :ok, %{state | entries: new_entries, tombstones: new_tombstones}}
        end

      _ ->
        {:reply, {:error, :not_a_member}, state}
    end
  end

  def handle_call({:member?, element}, _from, state) do
    {:reply, element_present?(state, element), state}
  end

  def handle_call(:members, _from, state) do
    {:reply, compute_members(state), state}
  end

  def handle_call({:merge, remote}, _from, local) do
    {:reply, :ok, merge_states(local, remote)}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp empty_state do
    %{entries: %{}, tombstones: MapSet.new(), clock: %{}}
  end

  defp element_present?(%{entries: entries}, element) do
    case Map.fetch(entries, element) do
      {:ok, tags} -> MapSet.size(tags) > 0
      :error -> false
    end
  end

  defp compute_members(%{entries: entries}) do
    entries
    |> Enum.filter(fn {_elem, tags} -> MapSet.size(tags) > 0 end)
    |> Enum.map(fn {elem, _tags} -> elem end)
    |> MapSet.new()
  end

  defp merge_states(local, remote) do
    # 1. Union the tombstones
    merged_tombstones = MapSet.union(local.tombstones, remote.tombstones)

    # 2. Union the entries per element, then subtract tombstones
    all_elements =
      MapSet.union(
        MapSet.new(Map.keys(local.entries)),
        MapSet.new(Map.keys(remote.entries))
      )

    merged_entries =
      Enum.reduce(all_elements, %{}, fn element, acc ->
        local_tags = Map.get(local.entries, element, MapSet.new())
        remote_tags = Map.get(remote.entries, element, MapSet.new())
        merged_tags = MapSet.union(local_tags, remote_tags)
        # Remove tombstoned tags
        live_tags = MapSet.difference(merged_tags, merged_tombstones)

        if MapSet.size(live_tags) > 0 do
          Map.put(acc, element, live_tags)
        else
          acc
        end
      end)

    # 3. Merge clocks by taking per-node max
    merged_clock =
      Map.merge(local.clock, remote.clock, fn _node, l, r -> max(l, r) end)

    %{entries: merged_entries, tombstones: merged_tombstones, clock: merged_clock}
  end
end
```
