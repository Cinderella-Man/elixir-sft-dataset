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
    Counter.increment(c, :a, 3)
    remote = %{p: %{a: 5, b: 2}, n: %{a: 1}}

    Counter.merge(c, remote)
    value_after_first = Counter.value(c)
    state_after_first = Counter.state(c)

    Counter.merge(c, remote)
    value_after_second = Counter.value(c)
    state_after_second = Counter.state(c)

    assert value_after_first == value_after_second
    assert state_after_first == state_after_second
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
end
