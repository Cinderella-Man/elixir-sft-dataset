defmodule ORSet do
  @moduledoc """
  A GenServer implementing an Observed-Remove Set (OR-Set / Add-Wins Set) CRDT.

  ## Overview

  An OR-Set is a Conflict-free Replicated Data Type (CRDT) that supports both
  add and remove operations with **add-wins** semantics: if one node adds an
  element while another concurrently removes it, the element remains in the set
  after merge.

  It achieves this by assigning a globally-unique tag to every add operation.
  Remove operations tombstone only the tags they can currently observe, so a
  concurrent add (with a fresh tag) survives the merge.

  ## Internal State

    - `entries`    — `%{element => MapSet.t({node_id, counter})}` active tags
    - `tombstones` — `MapSet.t({node_id, counter})` all removed tags
    - `clock`      — `%{node_id => counter}` per-node monotonic counter

  An element is present when it has at least one tag in `entries` that is not
  in `tombstones`.

  ## CRDT Merge Semantics

      merged.entries[elem] = union(local.entries[elem], remote.entries[elem])
                             \\ tombstones
      merged.tombstones     = union(local.tombstones, remote.tombstones)
      merged.clock[node]    = max(local.clock[node], remote.clock[node])

  This merge is idempotent, commutative, and associative.

  ## Example

      {:ok, s} = ORSet.start_link([])

      ORSet.add(s, :apple, :node_a)
      ORSet.add(s, :banana, :node_b)
      ORSet.remove(s, :apple)

      ORSet.members(s)
      #=> MapSet.new([:banana])

      # Re-adding :apple is allowed (generates a new tag)
      ORSet.add(s, :apple, :node_a)
      ORSet.members(s)
      #=> MapSet.new([:apple, :banana])
  """

  use GenServer

  @type element :: term()
  @type node_id :: term()
  @type tag :: {node_id(), pos_integer()}
  @type or_state :: %{
          entries: %{optional(element()) => MapSet.t(tag())},
          tombstones: MapSet.t(tag()),
          clock: %{optional(node_id()) => pos_integer()}
        }
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the ORSet process.

  ## Options

    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Adds `element` to the set, tagged with `node_id`.

  A unique tag `{node_id, counter}` is generated internally. If the element
  is already present, a new tag is added alongside existing ones. This is safe
  because each tag is unique.

  Returns `:ok`.
  """
  @spec add(server(), element(), node_id()) :: :ok
  def add(server, element, node_id) do
    GenServer.call(server, {:add, element, node_id})
  end

  @doc """
  Removes `element` from the set.

  All current tags for the element are moved to the tombstones set. Raises
  `ArgumentError` if the element is not currently a member.

  Returns `:ok`.
  """
  @spec remove(server(), element()) :: :ok
  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: it is not a current member of the OR-Set"
    end
  end

  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  @doc """
  Returns a `MapSet` of all elements currently in the set.
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end

  @doc """
  Merges a remote OR-Set state into the local state.

  `remote_state` must be a map with `:entries`, `:tombstones`, and `:clock` keys.

  Returns `:ok`.
  """
  @spec merge(server(), or_state()) :: :ok
  def merge(server, %{entries: entries, tombstones: tombstones, clock: clock} = _remote)
      when is_map(entries) and is_map(clock) do
    GenServer.call(server, {:merge, %{entries: entries, tombstones: MapSet.new(tombstones), clock: clock}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must have :entries, :tombstones, and :clock keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        entries:    %{element => MapSet.t({node_id, counter})},
        tombstones: MapSet.t({node_id, counter}),
        clock:      %{node_id => counter}
      }
  """
  @spec state(server()) :: or_state()
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

  @spec empty_state() :: or_state()
  defp empty_state do
    %{entries: %{}, tombstones: MapSet.new(), clock: %{}}
  end

  @spec element_present?(or_state(), element()) :: boolean()
  defp element_present?(%{entries: entries}, element) do
    case Map.fetch(entries, element) do
      {:ok, tags} -> MapSet.size(tags) > 0
      :error -> false
    end
  end

  @spec compute_members(or_state()) :: MapSet.t()
  defp compute_members(%{entries: entries}) do
    entries
    |> Enum.filter(fn {_elem, tags} -> MapSet.size(tags) > 0 end)
    |> Enum.map(fn {elem, _tags} -> elem end)
    |> MapSet.new()
  end

  @spec merge_states(or_state(), or_state()) :: or_state()
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
