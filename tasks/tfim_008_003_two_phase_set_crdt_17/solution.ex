  test "merge does not shrink sets (grow-only)", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :c)

    before_state = TwoPhaseSet.state(s)

    # Remote has fewer elements
    remote = %{added: MapSet.new([:a]), removed: MapSet.new()}
    TwoPhaseSet.merge(s, remote)

    after_state = TwoPhaseSet.state(s)

    # Sets only grow
    assert MapSet.subset?(before_state.added, after_state.added)
    assert MapSet.subset?(before_state.removed, after_state.removed)
  end