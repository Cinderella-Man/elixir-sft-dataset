  test "single add makes element a member", %{s: s} do
    assert :ok = TwoPhaseSet.add(s, :x)
    assert TwoPhaseSet.member?(s, :x) == true
    assert TwoPhaseSet.members(s) == MapSet.new([:x])
  end