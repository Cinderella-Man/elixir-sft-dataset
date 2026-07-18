# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TwoPhaseSet do
  @moduledoc """
  A GenServer implementing a Two-Phase Set (2P-Set) CRDT.

  ## Overview

  A 2P-Set is a Conflict-free Replicated Data Type (CRDT) that supports both
  add and remove operations on set elements. It achieves this by maintaining
  two grow-only sets (G-Sets):

    - `added`   — the set of all elements that have ever been added
    - `removed` — the "tombstone" set of all elements that have been removed

  An element is considered present when it is in `added` but not in `removed`.

  ## Key Constraint

  Once an element is removed, it can **never be re-added**. This permanent
  tombstone is the trade-off that gives the 2P-Set its simplicity: no causal
  metadata (vector clocks, unique tags, etc.) is required.

  ## CRDT Merge Semantics

  Merging two 2P-Set states is performed by computing the **set union** of
  each G-Set independently:

      merged.added   = union(local.added,   remote.added)
      merged.removed = union(local.removed, remote.removed)

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = TwoPhaseSet.start_link([])

      TwoPhaseSet.add(s, :alice)
      TwoPhaseSet.add(s, :bob)
      TwoPhaseSet.remove(s, :alice)

      TwoPhaseSet.members(s)
      #=> MapSet.new([:bob])

      # :alice can never be re-added
      TwoPhaseSet.add(s, :alice)
      #=> ** (ArgumentError) ...
  """

  use GenServer

  @type element :: term()
  @type tp_state :: %{added: MapSet.t(), removed: MapSet.t()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the TwoPhaseSet process.

  ## Options

    * `:name` — optional name for process registration.

  ## Examples

      {:ok, pid} = TwoPhaseSet.start_link([])
      {:ok, _}   = TwoPhaseSet.start_link(name: MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Adds `element` to the set.

  Raises `ArgumentError` if the element has previously been removed (tombstoned).
  Adding an element that is already present is a no-op.

  Returns `:ok`.
  """
  @spec add(server(), element()) :: :ok
  def add(server, element) do
    case GenServer.call(server, {:add, element}) do
      :ok ->
        :ok

      {:error, :tombstoned} ->
        raise ArgumentError,
              "cannot re-add element #{inspect(element)}: it was permanently removed"
    end
  end

  @doc """
  Removes `element` from the set.

  The element must be currently present (added and not yet removed). Raises
  `ArgumentError` if the element is not a current member.

  Returns `:ok`.
  """
  @spec remove(server(), element()) :: :ok
  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: not a current member"
    end
  end

  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when it is in the add-set but not the remove-set.
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
  Merges a remote 2P-Set state into the local state.

  `remote_state` must be a map of the form `%{added: MapSet, removed: MapSet}`.

  The merge computes the union of the add-sets and separately the union of the
  remove-sets. This ensures the merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), tp_state()) :: :ok
  def merge(server, %{added: added, removed: removed} = _remote_state) do
    GenServer.call(server, {:merge, %{added: MapSet.new(added), removed: MapSet.new(removed)}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :added and :removed keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        added:   MapSet of all elements ever added,
        removed: MapSet of all elements ever removed (tombstones)
      }

  This value can be sent to a remote node and passed to `TwoPhaseSet.merge/2`.
  """
  @spec state(server()) :: tp_state()
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
  def handle_call({:add, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(removed, element) do
      {:reply, {:error, :tombstoned}, state}
    else
      {:reply, :ok, %{state | added: MapSet.put(added, element)}}
    end
  end

  def handle_call({:remove, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(added, element) and not MapSet.member?(removed, element) do
      {:reply, :ok, %{state | removed: MapSet.put(removed, element)}}
    else
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

  @spec empty_state() :: tp_state()
  defp empty_state, do: %{added: MapSet.new(), removed: MapSet.new()}

  @spec element_present?(tp_state(), element()) :: boolean()
  defp element_present?(%{added: added, removed: removed}, element) do
    MapSet.member?(added, element) and not MapSet.member?(removed, element)
  end

  @spec compute_members(tp_state()) :: MapSet.t()
  defp compute_members(%{added: added, removed: removed}) do
    MapSet.difference(added, removed)
  end

  @spec merge_states(tp_state(), tp_state()) :: tp_state()
  defp merge_states(%{added: la, removed: lr}, %{added: ra, removed: rr}) do
    %{
      added: MapSet.union(la, ra),
      removed: MapSet.union(lr, rr)
    }
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule TwoPhaseSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = TwoPhaseSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.member?(s, :x) == true
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert TwoPhaseSet.member?(s, :missing) == false
  end

  test "remove after add removes element", %{s: s} do
    TwoPhaseSet.add(s, :x)
    assert :ok = TwoPhaseSet.remove(s, :x)
    assert TwoPhaseSet.member?(s, :x) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "adding an already-present element is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end

  # -------------------------------------------------------
  # 2P-Set constraint: no re-add after remove
  # -------------------------------------------------------

  test "re-adding a removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(s, :x)
    end
  end

  test "removing an element that was never added raises ArgumentError", %{s: s} do
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :never_added)
    end
  end

  test "removing an already-removed element raises ArgumentError", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :x)
    end
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :b)

    assert TwoPhaseSet.members(s) == MapSet.new([:a, :c])
    assert TwoPhaseSet.member?(s, :a) == true
    assert TwoPhaseSet.member?(s, :b) == false
    assert TwoPhaseSet.member?(s, :c) == true
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :y)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :added)
    assert Map.has_key?(state, :removed)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.added, :y)
    assert MapSet.member?(state.removed, :x)
    refute MapSet.member?(state.removed, :y)
  end

  test "state of a fresh set is empty MapSets", %{s: s} do
    state = TwoPhaseSet.state(s)
    assert state == %{added: MapSet.new(), removed: MapSet.new()}
  end

  test "tombstoned element remains in both added and removed sets", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.removed, :x)
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    remote = %{added: MapSet.new([:a, :b, :c]), removed: MapSet.new([:a])}
    assert :ok = TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end

  test "merge unions the add-sets and remove-sets", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)

    remote = %{added: MapSet.new([:b, :c]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    state = TwoPhaseSet.state(s)
    assert state.added == MapSet.new([:a, :b, :c])
    assert state.removed == MapSet.new([:a])
    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end

  test "merge introduces tombstones from remote that override local adds", %{s: s} do
    TwoPhaseSet.add(s, :a)
    assert TwoPhaseSet.member?(s, :a) == true

    # Remote has removed :a
    remote = %{added: MapSet.new([:a]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :a) == false
  end

  test "merge does not shrink sets (grow-only)", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :c)

    before_state = TwoPhaseSet.state(s)

    # Remote has fewer elements
    remote = %{added: MapSet.new([:a]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)

    after_state = TwoPhaseSet.state(s)

    # Sets only grow
    assert MapSet.subset?(before_state.added, after_state.added)
    assert MapSet.subset?(before_state.removed, after_state.removed)
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    TwoPhaseSet.add(s, :a)
    remote = %{added: MapSet.new([:a, :b]), removed: MapSet.new([:a])}

    TwoPhaseSet.merge(s, remote)
    members_after_first = TwoPhaseSet.members(s)
    state_after_first = TwoPhaseSet.state(s)

    TwoPhaseSet.merge(s, remote)
    members_after_second = TwoPhaseSet.members(s)
    state_after_second = TwoPhaseSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end

  test "merge is commutative" do
    {:ok, s1} = TwoPhaseSet.start_link([])
    {:ok, s2} = TwoPhaseSet.start_link([])

    # Node 1 operations
    TwoPhaseSet.add(s1, :x)
    TwoPhaseSet.add(s1, :y)
    TwoPhaseSet.remove(s1, :x)

    # Node 2 operations
    TwoPhaseSet.add(s2, :y)
    TwoPhaseSet.add(s2, :z)

    state1 = TwoPhaseSet.state(s1)
    state2 = TwoPhaseSet.state(s2)

    # Merge state2 into s1
    TwoPhaseSet.merge(s1, state2)

    # Merge state1 into s2
    TwoPhaseSet.merge(s2, state1)

    # Both should converge
    assert TwoPhaseSet.members(s1) == TwoPhaseSet.members(s2)
    assert TwoPhaseSet.state(s1) == TwoPhaseSet.state(s2)
  end

  test "merge is associative" do
    {:ok, sa} = TwoPhaseSet.start_link([])
    {:ok, sb} = TwoPhaseSet.start_link([])
    {:ok, sc} = TwoPhaseSet.start_link([])

    TwoPhaseSet.add(sa, :a)
    TwoPhaseSet.add(sb, :b)
    TwoPhaseSet.add(sb, :a)
    TwoPhaseSet.remove(sb, :a)
    TwoPhaseSet.add(sc, :c)

    sta = TwoPhaseSet.state(sa)
    stb = TwoPhaseSet.state(sb)
    stc = TwoPhaseSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(p1, sta)
    TwoPhaseSet.merge(p1, stb)
    TwoPhaseSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = TwoPhaseSet.start_link([])
    {:ok, temp} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(temp, stb)
    TwoPhaseSet.merge(temp, stc)
    bc_merged = TwoPhaseSet.state(temp)
    TwoPhaseSet.merge(p2, sta)
    TwoPhaseSet.merge(p2, bc_merged)

    assert TwoPhaseSet.members(p1) == TwoPhaseSet.members(p2)
    assert TwoPhaseSet.state(p1) == TwoPhaseSet.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    # TODO
  end

  test "merge propagates tombstones — locally-added element disappears after merge", %{} do
    {:ok, n1} = TwoPhaseSet.start_link([])
    {:ok, n2} = TwoPhaseSet.start_link([])

    # Both add :x
    TwoPhaseSet.add(n1, :x)
    TwoPhaseSet.add(n2, :x)

    # n2 removes :x
    TwoPhaseSet.remove(n2, :x)

    # n1 still has :x
    assert TwoPhaseSet.member?(n1, :x) == true

    # After merge, n1 learns about the tombstone
    TwoPhaseSet.merge(n1, TwoPhaseSet.state(n2))
    assert TwoPhaseSet.member?(n1, :x) == false

    # And :x can never be re-added on n1
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(n1, :x)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :a)
    before = TwoPhaseSet.state(s)
    TwoPhaseSet.merge(s, %{added: MapSet.new(), removed: MapSet.new()})
    assert TwoPhaseSet.state(s) == before
  end

  test "many elements", %{s: s} do
    for i <- 1..100 do
      TwoPhaseSet.add(s, :"elem_#{i}")
    end

    assert MapSet.size(TwoPhaseSet.members(s)) == 100
  end

  test "string elements work", %{s: s} do
    TwoPhaseSet.add(s, "hello")
    TwoPhaseSet.add(s, "world")
    assert TwoPhaseSet.member?(s, "hello") == true
    assert TwoPhaseSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = TwoPhaseSet.start_link(name: :my_2p_set)
    TwoPhaseSet.add(:my_2p_set, :x)
    assert TwoPhaseSet.member?(:my_2p_set, :x) == true
  end

  test "remove half the elements, verify membership", %{s: s} do
    elements = Enum.map(1..10, &:"e_#{&1}")
    Enum.each(elements, &TwoPhaseSet.add(s, &1))

    to_remove = Enum.take(elements, 5)
    Enum.each(to_remove, &TwoPhaseSet.remove(s, &1))

    remaining = Enum.drop(elements, 5) |> MapSet.new()
    assert TwoPhaseSet.members(s) == remaining
  end

  test "remote merge that re-adds a locally-removed element cannot resurrect it", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    # Remote never removed :x — it carries :x only in its add-set.
    remote = %{added: MapSet.new([:x]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :x) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "adding an element tombstoned via merge but never locally added raises", %{s: s} do
    remote = %{added: MapSet.new(), removed: MapSet.new([:ghost])}
    TwoPhaseSet.merge(s, remote)

    assert_raise ArgumentError, fn ->
      TwoPhaseSet.add(s, :ghost)
    end
  end

  test "element present only in the remove-set is not a member", %{s: s} do
    remote = %{added: MapSet.new(), removed: MapSet.new([:ghost])}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :ghost) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end

  test "adding a present element again returns :ok and does not change state", %{s: s} do
    TwoPhaseSet.add(s, :x)
    before = TwoPhaseSet.state(s)

    assert :ok = TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.state(s) == before
  end

  test "an element made a member only through merge can be removed", %{s: s} do
    remote = %{added: MapSet.new([:m]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)
    assert TwoPhaseSet.member?(s, :m) == true

    assert :ok = TwoPhaseSet.remove(s, :m)
    assert TwoPhaseSet.member?(s, :m) == false
  end
end
```
