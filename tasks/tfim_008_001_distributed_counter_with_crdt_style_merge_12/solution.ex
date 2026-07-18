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