  test "adding an already-present element is a no-op", %{s: s} do
    TwoPhaseSet.add(s, :x)
    TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end