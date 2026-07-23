# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule LWWSet do
  @moduledoc """
  A GenServer implementing a Last-Writer-Wins Element Set (LWW-Element-Set) CRDT.

  ## Overview

  An LWW-Element-Set is a Conflict-free Replicated Data Type (CRDT) that supports
  both add and remove operations on set elements in distributed systems where nodes
  may not be in constant communication.

  It works by maintaining two maps:
    - `adds`    — maps each element to the latest timestamp at which it was added
    - `removes` — maps each element to the latest timestamp at which it was removed

  An element is considered present in the set if its add timestamp is strictly
  greater than its remove timestamp (or if it has never been removed). On ties,
  the remove wins (remove-bias).

  ## CRDT Merge Semantics

  Merging two LWW-Element-Set states is performed by taking the **per-element
  maximum** of each timestamp map independently:

      merged.adds[elem]    = max(local.adds[elem],    remote.adds[elem])
      merged.removes[elem] = max(local.removes[elem], remote.removes[elem])

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = LWWSet.start_link([])

      LWWSet.add(s, :alice, 1)
      LWWSet.add(s, :bob, 2)
      LWWSet.remove(s, :alice, 3)

      LWWSet.members(s)
      #=> MapSet.new([:bob])

      remote = %{adds: %{charlie: 5}, removes: %{}}
      LWWSet.merge(s, remote)

      LWWSet.members(s)
      #=> MapSet.new([:bob, :charlie])
  """

  use GenServer

  @type element :: term()
  @type timestamp :: pos_integer()
  @type ts_map :: %{optional(element()) => pos_integer()}
  @type lww_state :: %{adds: ts_map(), removes: ts_map()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the LWWSet process.

  ## Options

    * `:name` — optional name for process registration, passed directly to
      `GenServer.start_link/3`. Accepts any valid `GenServer` name term
      (atom, `{:global, term}`, `{:via, module, term}`, etc.).

  ## Examples

      # Anonymous process
      {:ok, pid} = LWWSet.start_link([])

      # Named process
      {:ok, _} = LWWSet.start_link(name: MySet)
      LWWSet.members(MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Adds `element` to the set with the given `timestamp`.

  If the element already has a recorded add timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec add(server(), element(), timestamp()) :: :ok
  def add(server, element, timestamp) do
    validate_timestamp!(timestamp, :add)
    GenServer.call(server, {:add, element, timestamp})
  end

  @doc """
  Marks `element` as removed at the given `timestamp`.

  If the element already has a recorded remove timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec remove(server(), element(), timestamp()) :: :ok
  def remove(server, element, timestamp) do
    validate_timestamp!(timestamp, :remove)
    GenServer.call(server, {:remove, element, timestamp})
  end

  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when its add timestamp is strictly greater than its
  remove timestamp. If the timestamps are equal (tie), the element is
  considered absent (remove-wins bias).
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  @doc """
  Returns a `MapSet` of all elements currently in the set.

  An element is included when its add timestamp is strictly greater than its
  remove timestamp (or it has never been removed).
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end

  @doc """
  Merges a remote LWW-Element-Set state into the local state.

  `remote_state` must be a map of the form `%{adds: %{...}, removes: %{...}}`
  — i.e. the structure returned by `LWWSet.state/1`.

  For each element, the merge takes the **maximum** of the local and remote
  timestamps for both `adds` and `removes` independently. This ensures the
  merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), lww_state()) :: :ok
  def merge(server, %{adds: adds, removes: removes} = _remote_state)
      when is_map(adds) and is_map(removes) do
    GenServer.call(server, {:merge, %{adds: adds, removes: removes}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :adds and :removes keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        adds:    %{element => latest_add_timestamp, ...},
        removes: %{element => latest_remove_timestamp, ...}
      }

  This value can be sent to a remote node and passed to `LWWSet.merge/2`
  to synchronise state.
  """
  @spec state(server()) :: lww_state()
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
  def handle_call({:add, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:adds, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:remove, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:removes, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
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

  @spec empty_state() :: lww_state()
  defp empty_state, do: %{adds: %{}, removes: %{}}

  @spec element_present?(lww_state(), element()) :: boolean()
  defp element_present?(%{adds: adds, removes: removes}, element) do
    case Map.fetch(adds, element) do
      {:ok, add_ts} ->
        remove_ts = Map.get(removes, element, 0)
        add_ts > remove_ts

      :error ->
        false
    end
  end

  @spec compute_members(lww_state()) :: MapSet.t()
  defp compute_members(%{adds: adds, removes: removes}) do
    adds
    |> Enum.filter(fn {element, add_ts} ->
      remove_ts = Map.get(removes, element, 0)
      add_ts > remove_ts
    end)
    |> Enum.map(fn {element, _ts} -> element end)
    |> MapSet.new()
  end

  @spec merge_states(lww_state(), lww_state()) :: lww_state()
  defp merge_states(%{adds: la, removes: lr}, %{adds: ra, removes: rr}) do
    %{
      adds: merge_ts_maps(la, ra),
      removes: merge_ts_maps(lr, rr)
    }
  end

  # Merges two timestamp maps by taking the per-element maximum.
  @spec merge_ts_maps(ts_map(), ts_map()) :: ts_map()
  defp merge_ts_maps(local, remote) do
    Map.merge(local, remote, fn _element, l_ts, r_ts -> max(l_ts, r_ts) end)
  end

  @spec validate_timestamp!(term(), atom()) :: :ok
  defp validate_timestamp!(ts, _op) when is_integer(ts) and ts > 0, do: :ok

  defp validate_timestamp!(ts, op) do
    raise ArgumentError,
          "timestamp for #{op} must be a positive integer, got: #{inspect(ts)}"
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule LWWSetTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = LWWSet.start_link([])
    %{s: pid}
  end

  # -------------------------------------------------------
  # Basic add / remove / member? / members
  # -------------------------------------------------------

  test "fresh set has no members", %{s: s} do
    assert LWWSet.members(s) == MapSet.new()
  end

  test "single add makes element a member", %{s: s} do
    assert :ok = LWWSet.add(s, :x, 1)
    assert LWWSet.member?(s, :x) == true
    assert LWWSet.members(s) == MapSet.new([:x])
  end

  test "member? returns false for unknown element", %{s: s} do
    assert LWWSet.member?(s, :missing) == false
  end

  test "remove after add with higher timestamp removes element", %{s: s} do
    LWWSet.add(s, :x, 1)
    assert :ok = LWWSet.remove(s, :x, 2)
    assert LWWSet.member?(s, :x) == false
    assert LWWSet.members(s) == MapSet.new()
  end

  test "remove before add (lower timestamp) does not prevent membership", %{s: s} do
    LWWSet.remove(s, :x, 1)
    LWWSet.add(s, :x, 5)
    assert LWWSet.member?(s, :x) == true
  end

  test "add with higher timestamp after remove re-adds element", %{s: s} do
    LWWSet.add(s, :x, 1)
    LWWSet.remove(s, :x, 2)
    LWWSet.add(s, :x, 3)
    assert LWWSet.member?(s, :x) == true
  end

  test "remove-wins on equal timestamps (tie-breaking)", %{s: s} do
    LWWSet.add(s, :x, 5)
    LWWSet.remove(s, :x, 5)
    assert LWWSet.member?(s, :x) == false
  end

  # -------------------------------------------------------
  # Timestamp max semantics
  # -------------------------------------------------------

  test "repeated adds keep the maximum timestamp", %{s: s} do
    LWWSet.add(s, :x, 10)
    LWWSet.add(s, :x, 3)
    state = LWWSet.state(s)
    assert state.adds[:x] == 10
  end

  test "repeated removes keep the maximum timestamp", %{s: s} do
    LWWSet.remove(s, :x, 10)
    LWWSet.remove(s, :x, 3)
    state = LWWSet.state(s)
    assert state.removes[:x] == 10
  end

  # -------------------------------------------------------
  # Multiple elements
  # -------------------------------------------------------

  test "multiple elements tracked independently", %{s: s} do
    LWWSet.add(s, :a, 1)
    LWWSet.add(s, :b, 2)
    LWWSet.add(s, :c, 3)
    LWWSet.remove(s, :b, 4)

    assert LWWSet.members(s) == MapSet.new([:a, :c])
    assert LWWSet.member?(s, :a) == true
    assert LWWSet.member?(s, :b) == false
    assert LWWSet.member?(s, :c) == true
  end

  test "elements are tracked independently in state", %{s: s} do
    LWWSet.add(s, :a, 5)
    LWWSet.add(s, :b, 10)
    LWWSet.remove(s, :a, 3)

    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 10
    assert state.removes[:a] == 3
    assert state.removes[:b] == nil
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{s: s} do
    LWWSet.add(s, :x, 4)
    LWWSet.remove(s, :x, 2)

    state = LWWSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :adds)
    assert Map.has_key?(state, :removes)
    assert state.adds[:x] == 4
    assert state.removes[:x] == 2
  end

  test "state of a fresh set is empty maps", %{s: s} do
    state = LWWSet.state(s)
    assert state == %{adds: %{}, removes: %{}}
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty set", %{s: s} do
    remote = %{adds: %{a: 5, b: 3}, removes: %{a: 1}}
    assert :ok = LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b])
    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 3
    assert state.removes[:a] == 1
  end

  test "merge takes the max of each element's timestamps", %{s: s} do
    # Local: :a added at 3, removed at 1
    LWWSet.add(s, :a, 3)
    LWWSet.remove(s, :a, 1)

    # Remote: :a added at 5, no remove
    remote = %{adds: %{a: 5}, removes: %{}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    # max(3, 5) = 5
    assert state.adds[:a] == 5
    # max(1, 0) = 1 (remote has no remove, treat as absent)
    assert state.removes[:a] == 1
    assert LWWSet.member?(s, :a) == true
  end

  test "merge does not lower existing timestamps", %{s: s} do
    LWWSet.add(s, :a, 10)
    LWWSet.remove(s, :a, 7)

    # Remote has lower values
    remote = %{adds: %{a: 2}, removes: %{a: 3}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    assert state.adds[:a] == 10
    assert state.removes[:a] == 7
  end

  test "merge introduces new elements from remote", %{s: s} do
    LWWSet.add(s, :a, 1)
    remote = %{adds: %{b: 5, c: 3}, removes: %{c: 2}}
    LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b, :c])
  end

  test "merge where remote remove overrides local add", %{s: s} do
    LWWSet.add(s, :a, 5)
    remote = %{adds: %{}, removes: %{a: 10}}
    LWWSet.merge(s, remote)

    assert LWWSet.member?(s, :a) == false
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{s: s} do
    LWWSet.add(s, :a, 3)
    remote = %{adds: %{a: 5, b: 2}, removes: %{a: 1}}

    LWWSet.merge(s, remote)
    members_after_first = LWWSet.members(s)
    state_after_first = LWWSet.state(s)

    LWWSet.merge(s, remote)
    members_after_second = LWWSet.members(s)
    state_after_second = LWWSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end

  test "merge is commutative" do
    {:ok, s1} = LWWSet.start_link([])
    {:ok, s2} = LWWSet.start_link([])

    # Node 1 operations
    LWWSet.add(s1, :x, 5)
    LWWSet.remove(s1, :x, 2)
    LWWSet.add(s1, :y, 1)

    # Node 2 operations
    LWWSet.add(s2, :y, 8)
    LWWSet.remove(s2, :y, 3)
    LWWSet.add(s2, :x, 2)

    state1 = LWWSet.state(s1)
    state2 = LWWSet.state(s2)

    # Merge state2 into s1
    LWWSet.merge(s1, state2)

    # Merge state1 into s2
    LWWSet.merge(s2, state1)

    # Both should converge to the same members and state
    assert LWWSet.members(s1) == LWWSet.members(s2)
    assert LWWSet.state(s1) == LWWSet.state(s2)
  end

  test "merge is associative" do
    # TODO
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = LWWSet.start_link([])
    {:ok, node_b} = LWWSet.start_link([])

    # Node A: adds :user1 and :user2
    LWWSet.add(node_a, :user1, 1)
    LWWSet.add(node_a, :user2, 2)

    # Node B: adds :user3, removes :user1 (seen via earlier sync)
    LWWSet.add(node_b, :user3, 3)
    LWWSet.add(node_b, :user1, 1)
    LWWSet.remove(node_b, :user1, 4)

    # Before merge, each node only sees its own ops
    assert LWWSet.members(node_a) == MapSet.new([:user1, :user2])
    assert LWWSet.members(node_b) == MapSet.new([:user3])

    # Bidirectional merge (simulating gossip)
    state_a = LWWSet.state(node_a)
    state_b = LWWSet.state(node_b)
    LWWSet.merge(node_a, state_b)
    LWWSet.merge(node_b, state_a)

    # Both converge: user1 removed (remove at 4 > add at 1), user2 and user3 present
    assert LWWSet.members(node_a) == MapSet.new([:user2, :user3])
    assert LWWSet.members(node_b) == MapSet.new([:user2, :user3])
  end

  test "repeated merges after continued operations converge" do
    {:ok, n1} = LWWSet.start_link([])
    {:ok, n2} = LWWSet.start_link([])

    # Round 1
    LWWSet.add(n1, :a, 1)
    LWWSet.add(n2, :b, 2)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)
    assert LWWSet.members(n1) == MapSet.new([:a, :b])
    assert LWWSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: more operations after merge
    LWWSet.add(n1, :c, 3)
    LWWSet.remove(n2, :a, 4)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)

    # :a removed at 4 > added at 1, :b present, :c present
    assert LWWSet.members(n1) == MapSet.new([:b, :c])
    assert LWWSet.members(n2) == MapSet.new([:b, :c])
  end

  # -------------------------------------------------------
  # Argument validation
  # -------------------------------------------------------

  test "add with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.add(s, :x, -1)
    end
  end

  test "remove with non-positive timestamp raises", %{s: s} do
    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, 0)
    end

    assert_raise ArgumentError, fn ->
      LWWSet.remove(s, :x, -5)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated set is a no-op", %{s: s} do
    LWWSet.add(s, :a, 5)
    before = LWWSet.state(s)
    LWWSet.merge(s, %{adds: %{}, removes: %{}})
    assert LWWSet.state(s) == before
  end

  test "many elements with small timestamps", %{s: s} do
    for i <- 1..100 do
      LWWSet.add(s, :"elem_#{i}", 1)
    end

    assert MapSet.size(LWWSet.members(s)) == 100
  end

  test "large timestamps work correctly", %{s: s} do
    LWWSet.add(s, :a, 1_000_000)
    LWWSet.remove(s, :a, 999_999)
    assert LWWSet.member?(s, :a) == true
  end

  test "remove without prior add keeps element absent", %{s: s} do
    LWWSet.remove(s, :ghost, 10)
    assert LWWSet.member?(s, :ghost) == false
    state = LWWSet.state(s)
    assert state.removes[:ghost] == 10
    assert state.adds[:ghost] == nil
  end

  test "string elements work", %{s: s} do
    LWWSet.add(s, "hello", 1)
    LWWSet.add(s, "world", 2)
    assert LWWSet.member?(s, "hello") == true
    assert LWWSet.members(s) == MapSet.new(["hello", "world"])
  end

  test "named process registration works" do
    {:ok, _pid} = LWWSet.start_link(name: :my_lww_set)
    LWWSet.add(:my_lww_set, :x, 1)
    assert LWWSet.member?(:my_lww_set, :x) == true
  end

  test "add updates stored timestamp to a newer one", %{s: s} do
    LWWSet.add(s, :x, 3)
    LWWSet.add(s, :x, 10)
    state = LWWSet.state(s)
    assert state.adds[:x] == 10
    assert LWWSet.member?(s, :x) == true
  end
end
```
