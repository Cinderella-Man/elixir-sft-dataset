# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ORSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = ORSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert ORSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
    assert ORSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert ORSet.member?(s, :missing) == false
  end

  test "remove after add removes element", %{s: s} do
    ORSet.add(s, :x, :node_a)
    assert :ok = ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false
    assert ORSet.members(s) == MapSet.new()
  end

  test "removing non-member raises ArgumentError", %{s: s} do
    # TODO
  end

  # -------------------------------------------------------
  # OR-Set key property: re-add after remove
  # -------------------------------------------------------

  test "element can be re-added after removal", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end

  test "multiple add-remove cycles work", %{s: s} do
    for _i <- 1..5 do
      ORSet.add(s, :x, :node_a)
      assert ORSet.member?(s, :x) == true
      ORSet.remove(s, :x)
      assert ORSet.member?(s, :x) == false
    end

    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true
  end

  # -------------------------------------------------------
  # Unique tags
  # -------------------------------------------------------

  test "each add generates a unique tag", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_a)

    state = ORSet.state(s)
    tags = state.entries[:x]
    # Two adds from same node => two distinct tags
    assert MapSet.size(tags) == 2
  end

  test "tags from different nodes are distinct", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_b)

    state = ORSet.state(s)
    tags = state.entries[:x]
    assert MapSet.size(tags) == 2
  end

  test "clock increments per node", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_a)
    ORSet.add(s, :z, :node_b)

    state = ORSet.state(s)
    assert state.clock[:node_a] == 2
    assert state.clock[:node_b] == 1
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    ORSet.add(s, :a, :n1)
    ORSet.add(s, :b, :n1)
    ORSet.add(s, :c, :n1)
    ORSet.remove(s, :b)

    assert ORSet.members(s) == MapSet.new([:a, :c])
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_b)
    ORSet.remove(s, :x)

    state = ORSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :entries)
    assert Map.has_key?(state, :tombstones)
    assert Map.has_key?(state, :clock)

    # :x was removed, so its entry should be gone
    refute Map.has_key?(state.entries, :x)
    # :y should still have tags
    assert MapSet.size(state.entries[:y]) == 1
    # tombstones should have the tag from :x
    assert MapSet.size(state.tombstones) == 1
  end

  test "state of a fresh set is empty", %{s: s} do
    state = ORSet.state(s)
    assert state.entries == %{}
    assert state.tombstones == MapSet.new()
    assert state.clock == %{}
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    # Build a remote state manually
    remote = %{
      entries: %{a: MapSet.new([{:r, 1}]), b: MapSet.new([{:r, 2}])},
      tombstones: MapSet.new(),
      clock: %{r: 2}
    }

    assert :ok = ORSet.merge(s, remote)
    assert ORSet.members(s) == MapSet.new([:a, :b])
  end

  test "merge unions tags and tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    remote = %{
      entries: %{x: MapSet.new([{:remote, 1}])},
      tombstones: MapSet.new(),
      clock: %{remote: 1}
    }

    ORSet.merge(s, remote)

    state = ORSet.state(s)
    # Should have both tags for :x
    assert MapSet.size(state.entries[:x]) == 2
  end

  test "merge applies remote tombstones to local entries", %{s: s} do
    ORSet.add(s, :x, :local)
    local_state = ORSet.state(s)
    local_tag = local_state.entries[:x] |> MapSet.to_list() |> hd()

    # Remote has tombstoned that exact tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([local_tag]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == false
  end

  test "merge does not remove entries with tags not in tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    # Remote tombstones a different tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([{:other_node, 999}]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == true
  end

  # -------------------------------------------------------
  # Add-wins semantics (the key OR-Set property)
  # -------------------------------------------------------

  test "concurrent add and remove: add wins" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Both start with :x
    ORSet.add(node_a, :x, :a)
    state_a = ORSet.state(node_a)
    ORSet.merge(node_b, state_a)

    # Now both have :x with tag {:a, 1}
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true

    # CONCURRENT: node_a re-adds :x (new tag {:a, 2}), node_b removes :x
    ORSet.add(node_a, :x, :a)
    ORSet.remove(node_b, :x)

    # node_a: :x has tags [{:a, 1}, {:a, 2}]
    # node_b: :x removed (tombstones: [{:a, 1}])
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == false

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # ADD WINS: :x is present because {:a, 2} is NOT in node_b's tombstones
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    ORSet.add(s, :a, :n1)
    remote = %{
      entries: %{b: MapSet.new([{:n2, 1}])},
      tombstones: MapSet.new(),
      clock: %{n2: 1}
    }

    ORSet.merge(s, remote)
    members_first = ORSet.members(s)
    state_first = ORSet.state(s)

    ORSet.merge(s, remote)
    members_second = ORSet.members(s)
    state_second = ORSet.state(s)

    assert members_first == members_second
    assert state_first == state_second
  end

  test "merge is commutative" do
    {:ok, s1} = ORSet.start_link([])
    {:ok, s2} = ORSet.start_link([])

    ORSet.add(s1, :x, :n1)
    ORSet.add(s1, :y, :n1)

    ORSet.add(s2, :y, :n2)
    ORSet.add(s2, :z, :n2)
    ORSet.remove(s2, :y)

    state1 = ORSet.state(s1)
    state2 = ORSet.state(s2)

    # Merge in both directions
    ORSet.merge(s1, state2)
    ORSet.merge(s2, state1)

    assert ORSet.members(s1) == ORSet.members(s2)
    assert ORSet.state(s1) == ORSet.state(s2)
  end

  test "merge is associative" do
    {:ok, sa} = ORSet.start_link([])
    {:ok, sb} = ORSet.start_link([])
    {:ok, sc} = ORSet.start_link([])

    ORSet.add(sa, :a, :n1)
    ORSet.add(sb, :b, :n2)
    ORSet.add(sc, :c, :n3)
    ORSet.add(sc, :a, :n3)

    sta = ORSet.state(sa)
    stb = ORSet.state(sb)
    stc = ORSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = ORSet.start_link([])
    ORSet.merge(p1, sta)
    ORSet.merge(p1, stb)
    ORSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = ORSet.start_link([])
    {:ok, temp} = ORSet.start_link([])
    ORSet.merge(temp, stb)
    ORSet.merge(temp, stc)
    bc_merged = ORSet.state(temp)
    ORSet.merge(p2, sta)
    ORSet.merge(p2, bc_merged)

    assert ORSet.members(p1) == ORSet.members(p2)
    assert ORSet.state(p1) == ORSet.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Node A adds users
    ORSet.add(node_a, :alice, :a)
    ORSet.add(node_a, :bob, :a)

    # Node B adds users
    ORSet.add(node_b, :charlie, :b)
    ORSet.add(node_b, :bob, :b)

    # Before merge
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob])
    assert ORSet.members(node_b) == MapSet.new([:charlie, :bob])

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # Both converge to all users
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob, :charlie])
    assert ORSet.members(node_b) == MapSet.new([:alice, :bob, :charlie])
  end

  test "repeated merges after continued operations converge" do
    {:ok, n1} = ORSet.start_link([])
    {:ok, n2} = ORSet.start_link([])

    # Round 1
    ORSet.add(n1, :a, :n1)
    ORSet.add(n2, :b, :n2)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)
    assert ORSet.members(n1) == MapSet.new([:a, :b])
    assert ORSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: n1 adds :c, n2 removes :a
    ORSet.add(n1, :c, :n1)
    ORSet.remove(n2, :a)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)

    # :a removed, :b and :c remain
    assert ORSet.members(n1) == MapSet.new([:b, :c])
    assert ORSet.members(n2) == MapSet.new([:b, :c])
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    ORSet.add(s, :a, :n1)
    before = ORSet.state(s)
    ORSet.merge(s, %{entries: %{}, tombstones: MapSet.new(), clock: %{}})
    assert ORSet.state(s) == before
  end

  test "many elements", %{s: s} do
    for i <- 1..100 do
      ORSet.add(s, :"elem_#{i}", :node)
    end

    assert MapSet.size(ORSet.members(s)) == 100
  end

  test "string elements work", %{s: s} do
    ORSet.add(s, "hello", :n1)
    ORSet.add(s, "world", :n1)
    assert ORSet.member?(s, "hello") == true
    assert ORSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = ORSet.start_link(name: :my_or_set)
    ORSet.add(:my_or_set, :x, :n1)
    assert ORSet.member?(:my_or_set, :x) == true
  end

  test "removing then re-adding from same node works", %{s: s} do
    ORSet.add(s, :x, :n1)
    ORSet.remove(s, :x)
    ORSet.add(s, :x, :n1)

    state = ORSet.state(s)
    # Old tag is in tombstones, new tag is in entries
    assert MapSet.size(state.tombstones) == 1
    assert MapSet.size(state.entries[:x]) == 1

    # The live tag should NOT be in tombstones
    live_tag = state.entries[:x] |> MapSet.to_list() |> hd()
    refute MapSet.member?(state.tombstones, live_tag)
  end
end
```
