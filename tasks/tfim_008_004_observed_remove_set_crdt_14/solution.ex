  test "state of a fresh set is empty", %{s: s} do
    state = ORSet.state(s)
    assert state.entries == %{}
    assert state.tombstones == MapSet.new()
    assert state.clock == %{}
  end