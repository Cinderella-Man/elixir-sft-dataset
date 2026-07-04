  test "multiple elements tracked independently", %{s: s} do
    TwoPhaseSet.add(s, :a)
    TwoPhaseSet.add(s, :b)
    TwoPhaseSet.add(s, :c)
    TwoPhaseSet.remove(s, :b)

    assert TwoPhaseSet.members(s) == MapSet.new([:a, :c])
    assert TwoPhaseSet.member?(s, :a) == true
    assert TwoPhaseSet.member?(s, :b) == false
    assert TwoPhaseSet.member?(s, :c) == true
  end