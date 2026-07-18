  test "remove without prior add keeps element absent", %{s: s} do
    LWWSet.remove(s, :ghost, 10)
    assert LWWSet.member?(s, :ghost) == false
    state = LWWSet.state(s)
    assert state.removes[:ghost] == 10
    assert state.adds[:ghost] == nil
  end