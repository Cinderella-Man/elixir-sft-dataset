  test "state returns the correct shape", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :y)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :added)
    assert Map.has_key?(state, :removed)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.added, :y)
    assert MapSet.member?(state.removed, :x)
    refute MapSet.member?(state.removed, :y)
  end