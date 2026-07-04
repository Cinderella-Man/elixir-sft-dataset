  test "repeated adds keep the maximum timestamp", %{s: s} do
    LWWSet.add(s, :x, 10)
    LWWSet.add(s, :x, 3)
    state = LWWSet.state(s)
    assert state.adds[:x] == 10
  end