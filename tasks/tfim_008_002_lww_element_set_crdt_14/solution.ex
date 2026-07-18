  test "state of a fresh set is empty maps", %{s: s} do
    state = LWWSet.state(s)
    assert state == %{adds: %{}, removes: %{}}
  end