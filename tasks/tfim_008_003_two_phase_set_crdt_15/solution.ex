  test "merge unions the add-sets and remove-sets", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)

    remote = %{added: MapSet.new([:b, :c]), removed: MapSet.new([:a])}
    TwoPhaseSet.merge(s, remote)

    state = TwoPhaseSet.state(s)
    assert state.added == MapSet.new([:a, :b, :c])
    assert state.removed == MapSet.new([:a])
    assert TwoPhaseSet.members(s) == MapSet.new([:b, :c])
  end