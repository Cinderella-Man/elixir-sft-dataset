  test "merge is commutative" do
    {:ok, s1} = TwoPhaseSet.start_link([])
    {:ok, s2} = TwoPhaseSet.start_link([])

    # Node 1 operations
    TwoPhaseSet.add(s1, :x)
    TwoPhaseSet.add(s1, :y)
    TwoPhaseSet.remove(s1, :x)

    # Node 2 operations
    TwoPhaseSet.add(s2, :y)
    TwoPhaseSet.add(s2, :z)

    state1 = TwoPhaseSet.state(s1)
    state2 = TwoPhaseSet.state(s2)

    # Merge state2 into s1
    TwoPhaseSet.merge(s1, state2)

    # Merge state1 into s2
    TwoPhaseSet.merge(s2, state1)

    # Both should converge
    assert TwoPhaseSet.members(s1) == TwoPhaseSet.members(s2)
    assert TwoPhaseSet.state(s1) == TwoPhaseSet.state(s2)
  end