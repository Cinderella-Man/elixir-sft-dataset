# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Counter do
  @moduledoc """
  A GenServer implementing a PN-Counter (Positive-Negative Counter) CRDT.

  ## Overview

  A PN-Counter is a Conflict-free Replicated Data Type (CRDT) that supports
  both increment and decrement operations in distributed systems where nodes
  may not be in constant communication.

  It works by maintaining two grow-only counters (G-Counters):
    - `p` — tracks all increments per node
    - `n` — tracks all decrements per node

  The observable value is `sum(p) - sum(n)`.

  ## CRDT Merge Semantics

  Merging two PN-Counter states is performed by taking the **per-node maximum**
  of each G-Counter independently:

      merged.p[node] = max(local.p[node], remote.p[node])
      merged.n[node] = max(local.n[node], remote.n[node])

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = Counter.start_link([])

      Counter.increment(s, :node_a, 5)
      Counter.increment(s, :node_b, 3)
      Counter.decrement(s, :node_a, 2)

      Counter.value(s)
      #=> 6  (i.e. (5 + 3) - 2)

      remote = %{p: %{node_c: 10}, n: %{node_c: 4}}
      Counter.merge(s, remote)

      Counter.value(s)
      #=> 12  (i.e. (5 + 3 + 10) - (2 + 4))
  """

  use GenServer

  @type node_id :: term()
  @type amount :: pos_integer()
  @type g_counter :: %{optional(node_id()) => non_neg_integer()}
  @type pn_state :: %{p: g_counter(), n: g_counter()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the Counter process.

  ## Options

    * `:name` — optional name for process registration, passed directly to
      `GenServer.start_link/3`. Accepts any valid `GenServer` name term
      (atom, `{:global, term}`, `{:via, module, term}`, etc.).

  ## Examples

      # Anonymous process
      {:ok, pid} = Counter.start_link([])

      # Named process
      {:ok, _} = Counter.start_link(name: MyCounter)
      Counter.value(MyCounter)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} =
      Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Increments the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec increment(server(), node_id(), amount()) :: :ok
  def increment(server, node_id, amount \\ 1) do
    validate_amount!(amount, :increment)
    GenServer.call(server, {:increment, node_id, amount})
  end

  @doc """
  Decrements the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec decrement(server(), node_id(), amount()) :: :ok
  def decrement(server, node_id, amount \\ 1) do
    validate_amount!(amount, :decrement)
    GenServer.call(server, {:decrement, node_id, amount})
  end

  @doc """
  Returns the current integer value of the counter.

  Computed as `sum(p values) - sum(n values)` across all nodes.
  """
  @spec value(server()) :: integer()
  def value(server) do
    GenServer.call(server, :value)
  end

  @doc """
  Merges a remote PN-Counter state into the local state.

  `remote_state` must be a map of the form `%{p: %{...}, n: %{...}}` —
  i.e. the structure returned by `Counter.state/1`.

  For each node, the merge takes the **maximum** of the local and remote
  values for both `p` and `n` independently. This ensures the merge is
  idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), pn_state()) :: :ok
  def merge(server, %{p: p, n: n} = _remote_state)
      when is_map(p) and is_map(n) do
    GenServer.call(server, {:merge, %{p: p, n: n}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :p and :n keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the counter.

  The returned map has the form:

      %{
        p: %{node_id => total_increments, ...},
        n: %{node_id => total_decrements, ...}
      }

  This value can be sent to a remote node and passed to `Counter.merge/2`
  to synchronise state.
  """
  @spec state(server()) :: pn_state()
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
  def handle_call({:increment, node_id, amount}, _from, state) do
    new_state = update_in(state, [:p, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call({:decrement, node_id, amount}, _from, state) do
    new_state = update_in(state, [:n, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call(:value, _from, state) do
    {:reply, compute_value(state), state}
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

  @spec empty_state() :: pn_state()
  defp empty_state, do: %{p: %{}, n: %{}}

  @spec compute_value(pn_state()) :: integer()
  defp compute_value(%{p: p, n: n}) do
    sum_map(p) - sum_map(n)
  end

  @spec sum_map(g_counter()) :: non_neg_integer()
  defp sum_map(map), do: Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)

  @spec merge_states(pn_state(), pn_state()) :: pn_state()
  defp merge_states(%{p: lp, n: ln}, %{p: rp, n: rn}) do
    %{
      p: merge_g_counters(lp, rp),
      n: merge_g_counters(ln, rn)
    }
  end

  # Merges two G-Counters by taking the per-node maximum.
  @spec merge_g_counters(g_counter(), g_counter()) :: g_counter()
  defp merge_g_counters(local, remote) do
    Map.merge(local, remote, fn _node_id, l_val, r_val -> max(l_val, r_val) end)
  end

  @spec validate_amount!(term(), atom()) :: :ok
  defp validate_amount!(amount, _op) when is_integer(amount) and amount > 0, do: :ok

  defp validate_amount!(amount, op) do
    raise ArgumentError,
          "amount for #{op} must be a positive integer, got: #{inspect(amount)}"
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CounterTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = Counter.start_link([])
    %{c: pid}
  end

  # -------------------------------------------------------
  # Basic increment / decrement / value
  # -------------------------------------------------------

  test "fresh counter has value 0", %{c: c} do
    assert Counter.value(c) == 0
  end

  test "single increment", %{c: c} do
    assert :ok = Counter.increment(c, :a)
    assert Counter.value(c) == 1
  end

  test "single decrement", %{c: c} do
    assert :ok = Counter.decrement(c, :a)
    assert Counter.value(c) == -1
  end

  test "increment with explicit amount", %{c: c} do
    Counter.increment(c, :a, 5)
    assert Counter.value(c) == 5
  end

  test "decrement with explicit amount", %{c: c} do
    Counter.decrement(c, :a, 3)
    assert Counter.value(c) == -3
  end

  test "increments accumulate for the same node", %{c: c} do
    Counter.increment(c, :a, 2)
    Counter.increment(c, :a, 3)
    assert Counter.value(c) == 5
  end

  test "mixed increment and decrement on one node", %{c: c} do
    Counter.increment(c, :a, 10)
    Counter.decrement(c, :a, 4)
    assert Counter.value(c) == 6
  end

  test "value can go negative", %{c: c} do
    Counter.increment(c, :a, 2)
    Counter.decrement(c, :a, 7)
    assert Counter.value(c) == -5
  end

  # -------------------------------------------------------
  # Multiple nodes
  # -------------------------------------------------------

  test "multiple nodes contribute to the value", %{c: c} do
    Counter.increment(c, :a, 3)
    Counter.increment(c, :b, 5)
    Counter.decrement(c, :a, 1)
    Counter.decrement(c, :b, 2)
    # value = (3 + 5) - (1 + 2) = 5
    assert Counter.value(c) == 5
  end

  test "nodes are tracked independently in state", %{c: c} do
    Counter.increment(c, :a, 3)
    Counter.increment(c, :b, 7)
    Counter.decrement(c, :a, 1)

    state = Counter.state(c)
    assert state.p[:a] == 3
    assert state.p[:b] == 7
    assert state.n[:a] == 1
    # :b never decremented
    assert state.n[:b] == nil
  end

  # -------------------------------------------------------
  # State structure
  # -------------------------------------------------------

  test "state returns the correct shape", %{c: c} do
    Counter.increment(c, :x, 4)
    Counter.decrement(c, :x, 2)

    state = Counter.state(c)
    assert is_map(state)
    assert Map.has_key?(state, :p)
    assert Map.has_key?(state, :n)
    assert state.p[:x] == 4
    assert state.n[:x] == 2
  end

  test "state of a fresh counter is empty maps", %{c: c} do
    state = Counter.state(c)
    assert state == %{p: %{}, n: %{}}
  end

  # -------------------------------------------------------
  # Merge basics
  # -------------------------------------------------------

  test "merging a remote state into an empty counter", %{c: c} do
    remote = %{p: %{a: 5, b: 3}, n: %{a: 1}}
    assert :ok = Counter.merge(c, remote)

    assert Counter.value(c) == 5 + 3 - 1
    state = Counter.state(c)
    assert state.p[:a] == 5
    assert state.p[:b] == 3
    assert state.n[:a] == 1
  end

  test "merge takes the max of each node's counts", %{c: c} do
    # Local: node :a has incremented 3, decremented 1
    Counter.increment(c, :a, 3)
    Counter.decrement(c, :a, 1)

    # Remote: node :a has incremented 5, decremented 0
    remote = %{p: %{a: 5}, n: %{}}
    Counter.merge(c, remote)

    state = Counter.state(c)
    # max(3, 5) = 5
    assert state.p[:a] == 5
    # max(1, 0) = 1  (remote has no decrement, treat as 0)
    assert state.n[:a] == 1
    assert Counter.value(c) == 5 - 1
  end

  test "merge does not lower existing counts", %{c: c} do
    Counter.increment(c, :a, 10)
    Counter.decrement(c, :a, 7)

    # Remote has lower values
    remote = %{p: %{a: 2}, n: %{a: 3}}
    Counter.merge(c, remote)

    state = Counter.state(c)
    # kept the local (higher)
    assert state.p[:a] == 10
    # kept the local (higher)
    assert state.n[:a] == 7
  end

  # -------------------------------------------------------
  # Merge: CRDT properties
  # -------------------------------------------------------

  test "merge is idempotent", %{c: c} do
    # TODO
  end

  test "merge is commutative" do
    # Simulate two nodes with separate counter processes
    {:ok, c1} = Counter.start_link([])
    {:ok, c2} = Counter.start_link([])

    # Node 1 operations
    Counter.increment(c1, :node1, 5)
    Counter.decrement(c1, :node1, 2)
    Counter.increment(c1, :node2, 1)

    # Node 2 operations
    Counter.increment(c2, :node2, 8)
    Counter.decrement(c2, :node2, 3)
    Counter.increment(c2, :node1, 2)

    state1 = Counter.state(c1)
    state2 = Counter.state(c2)

    # Merge state2 into c1
    Counter.merge(c1, state2)

    # Merge state1 into c2
    Counter.merge(c2, state1)

    # Both should converge to the same value
    assert Counter.value(c1) == Counter.value(c2)
    assert Counter.state(c1) == Counter.state(c2)
  end

  test "merge is associative" do
    # Three separate counter states
    {:ok, ca} = Counter.start_link([])
    {:ok, cb} = Counter.start_link([])
    {:ok, cc} = Counter.start_link([])

    Counter.increment(ca, :a, 3)
    Counter.increment(cb, :b, 5)
    Counter.decrement(cb, :a, 2)
    Counter.increment(cc, :c, 7)
    Counter.decrement(cc, :b, 1)

    sa = Counter.state(ca)
    sb = Counter.state(cb)
    sc = Counter.state(cc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = Counter.start_link([])
    Counter.merge(p1, sa)
    Counter.merge(p1, sb)
    Counter.merge(p1, sc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = Counter.start_link([])
    {:ok, temp} = Counter.start_link([])
    Counter.merge(temp, sb)
    Counter.merge(temp, sc)
    bc_merged = Counter.state(temp)
    Counter.merge(p2, sa)
    Counter.merge(p2, bc_merged)

    assert Counter.value(p1) == Counter.value(p2)
    assert Counter.state(p1) == Counter.state(p2)
  end

  # -------------------------------------------------------
  # Simulated distributed scenario
  # -------------------------------------------------------

  test "two-node simulation with divergent ops then merge", %{} do
    {:ok, node_a} = Counter.start_link([])
    {:ok, node_b} = Counter.start_link([])

    # Node A: 10 likes
    Counter.increment(node_a, :a, 10)
    # Node B: 5 likes and 2 unlikes
    Counter.increment(node_b, :b, 5)
    Counter.decrement(node_b, :b, 2)

    # Before merge, each node only sees its own ops
    assert Counter.value(node_a) == 10
    assert Counter.value(node_b) == 3

    # Bidirectional merge (simulating gossip)
    state_a = Counter.state(node_a)
    state_b = Counter.state(node_b)
    Counter.merge(node_a, state_b)
    Counter.merge(node_b, state_a)

    # Both converge to 10 + 5 - 2 = 13
    assert Counter.value(node_a) == 13
    assert Counter.value(node_b) == 13
  end

  test "repeated merges after continued operations converge", %{} do
    {:ok, n1} = Counter.start_link([])
    {:ok, n2} = Counter.start_link([])

    # Round 1
    Counter.increment(n1, :n1, 3)
    Counter.increment(n2, :n2, 4)

    s1 = Counter.state(n1)
    s2 = Counter.state(n2)
    Counter.merge(n1, s2)
    Counter.merge(n2, s1)
    assert Counter.value(n1) == 7
    assert Counter.value(n2) == 7

    # Round 2: more operations after merge
    Counter.increment(n1, :n1, 2)
    Counter.decrement(n2, :n2, 1)

    s1 = Counter.state(n1)
    s2 = Counter.state(n2)
    Counter.merge(n1, s2)
    Counter.merge(n2, s1)

    # n1 increments: 3+2=5, n2 increments: 4, n2 decrements: 1
    # value = 5 + 4 - 1 = 8
    assert Counter.value(n1) == 8
    assert Counter.value(n2) == 8
  end

  # -------------------------------------------------------
  # Argument validation
  # -------------------------------------------------------

  test "increment with non-positive amount raises", %{c: c} do
    assert_raise ArgumentError, fn ->
      Counter.increment(c, :a, 0)
    end

    assert_raise ArgumentError, fn ->
      Counter.increment(c, :a, -1)
    end
  end

  test "decrement with non-positive amount raises", %{c: c} do
    assert_raise ArgumentError, fn ->
      Counter.decrement(c, :a, 0)
    end

    assert_raise ArgumentError, fn ->
      Counter.decrement(c, :a, -5)
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "merging empty state into populated counter is a no-op", %{c: c} do
    Counter.increment(c, :a, 5)
    before = Counter.state(c)
    Counter.merge(c, %{p: %{}, n: %{}})
    assert Counter.state(c) == before
  end

  test "many nodes with small counts", %{c: c} do
    for i <- 1..100 do
      Counter.increment(c, :"node_#{i}", 1)
    end

    assert Counter.value(c) == 100
  end

  test "large amounts work correctly", %{c: c} do
    Counter.increment(c, :a, 1_000_000)
    Counter.decrement(c, :a, 999_999)
    assert Counter.value(c) == 1
  end

  test "default amount is 1 for both increment and decrement", %{c: c} do
    Counter.increment(c, :a)
    Counter.increment(c, :a)
    Counter.decrement(c, :a)
    assert Counter.value(c) == 1
  end

  test "start_link registers the process under the given :name" do
    name = :"counter_name_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Counter.start_link(name: name)
    assert :ok = Counter.increment(name, :a, 3)
    assert :ok = Counter.decrement(name, :a, 1)
    assert Counter.value(name) == 2
    assert Counter.state(name) == %{p: %{a: 3}, n: %{a: 1}}
  end

  test "documented example yields the exact state map and value", %{c: c} do
    Counter.increment(c, :a, 3)
    Counter.decrement(c, :a, 1)
    assert Counter.state(c) == %{p: %{a: 3}, n: %{a: 1}}
    assert Counter.value(c) == 2
  end
end
```
