  test "merging empty state into populated set is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :a)
    before = TwoPhaseSet.state(s)
    TwoPhaseSet.merge(s, %{added: MapSet.new(), removed: MapSet.new()})
    assert TwoPhaseSet.state(s) == before
  end