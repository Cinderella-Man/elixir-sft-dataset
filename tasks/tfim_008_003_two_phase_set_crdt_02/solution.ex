  test "fresh set has no members", %{s: s} do
    assert TwoPhaseSet.members(s) == MapSet.new()
  end