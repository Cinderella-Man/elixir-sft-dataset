  test "repeated removes keep the maximum timestamp", %{s: s} do
    LWWSet.remove(s, :x, 10)
    LWWSet.remove(s, :x, 3)
    state = LWWSet.state(s)
    assert state.removes[:x] == 10
  end