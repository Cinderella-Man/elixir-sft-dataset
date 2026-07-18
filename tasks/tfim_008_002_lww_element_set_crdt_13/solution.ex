  test "state returns the correct shape", %{s: s} do
    LWWSet.add(s, :x, 4)
    LWWSet.remove(s, :x, 2)

    state = LWWSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :adds)
    assert Map.has_key?(state, :removes)
    assert state.adds[:x] == 4
    assert state.removes[:x] == 2
  end