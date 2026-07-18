  test "tombstoned element remains in both added and removed sets", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.remove(s, :x)

    state = TwoPhaseSet.state(s)
    assert MapSet.member?(state.added, :x)
    assert MapSet.member?(state.removed, :x)
  end