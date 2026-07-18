  test "string elements work", %{s: s} do
    TwoPhaseSet.add(s, "hello")
    TwoPhaseSet.add(s, "world")
    assert TwoPhaseSet.member?(s, "hello") == true
    assert TwoPhaseSet.members(s) == MapSet.new(["hello", "world"])
  end