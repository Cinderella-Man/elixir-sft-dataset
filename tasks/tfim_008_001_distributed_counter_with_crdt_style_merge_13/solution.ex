  test "state of a fresh counter is empty maps", %{c: c} do
    state = Counter.state(c)
    assert state == %{p: %{}, n: %{}}
  end