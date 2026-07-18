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