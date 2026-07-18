  test "state of a fresh set is empty MapSets", %{s: s} do
    state = TwoPhaseSet.state(s)
    assert state == %{added: MapSet.new(), removed: MapSet.new()}
  end