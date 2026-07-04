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