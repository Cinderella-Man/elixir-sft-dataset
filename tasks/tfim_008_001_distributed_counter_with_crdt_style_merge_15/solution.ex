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