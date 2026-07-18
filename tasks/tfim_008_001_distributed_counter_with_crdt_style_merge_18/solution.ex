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