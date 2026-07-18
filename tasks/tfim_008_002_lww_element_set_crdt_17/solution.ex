  test "merge does not lower existing timestamps", %{s: s} do
    LWWSet.add(s, :a, 10)
    LWWSet.remove(s, :a, 7)

    # Remote has lower values
    remote = %{adds: %{a: 2}, removes: %{a: 3}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    assert state.adds[:a] == 10
    assert state.removes[:a] == 7
  end