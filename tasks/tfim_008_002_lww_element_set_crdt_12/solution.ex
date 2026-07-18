  test "elements are tracked independently in state", %{s: s} do
    LWWSet.add(s, :a, 5)
    LWWSet.add(s, :b, 10)
    LWWSet.remove(s, :a, 3)

    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 10
    assert state.removes[:a] == 3
    assert state.removes[:b] == nil
  end