  test "remove after add removes element", %{s: s} do
    TwoPhaseSet.add(s, :x)
    assert :ok = TwoPhaseSet.remove(s, :x)
    assert TwoPhaseSet.member?(s, :x) == false
    assert TwoPhaseSet.members(s) == MapSet.new()
  end