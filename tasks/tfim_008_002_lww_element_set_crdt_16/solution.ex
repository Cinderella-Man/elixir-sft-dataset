  test "merge takes the max of each element's timestamps", %{s: s} do
    # Local: :a added at 3, removed at 1
    LWWSet.add(s, :a, 3)
    LWWSet.remove(s, :a, 1)

    # Remote: :a added at 5, no remove
    remote = %{adds: %{a: 5}, removes: %{}}
    LWWSet.merge(s, remote)

    state = LWWSet.state(s)
    # max(3, 5) = 5
    assert state.adds[:a] == 5
    # max(1, 0) = 1 (remote has no remove, treat as absent)
    assert state.removes[:a] == 1
    assert LWWSet.member?(s, :a) == true
  end