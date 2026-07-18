  test "merge is idempotent", %{s: s} do
    TwoPhaseSet.add(s, :a)
    remote = %{added: MapSet.new([:a, :b]), removed: MapSet.new([:a])}

    TwoPhaseSet.merge(s, remote)
    members_after_first = TwoPhaseSet.members(s)
    state_after_first = TwoPhaseSet.state(s)

    TwoPhaseSet.merge(s, remote)
    members_after_second = TwoPhaseSet.members(s)
    state_after_second = TwoPhaseSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end