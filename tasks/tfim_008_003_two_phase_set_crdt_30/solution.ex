  test "element present only in the remove-set is not a member", %{s: s} do
    remote = %{added: MapSet.new(), removed: MapSet.new([:ghost])}
    TwoPhaseSet.merge(s, remote)

    assert TwoPhaseSet.member?(s, :ghost) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end