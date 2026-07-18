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