  test "merge is commutative" do
    {:ok, s1} = ORSet.start_link([])
    {:ok, s2} = ORSet.start_link([])

    ORSet.add(s1, :x, :n1)
    ORSet.add(s1, :y, :n1)

    ORSet.add(s2, :y, :n2)
    ORSet.add(s2, :z, :n2)
    ORSet.remove(s2, :y)

    state1 = ORSet.state(s1)
    state2 = ORSet.state(s2)

    # Merge in both directions
    ORSet.merge(s1, state2)
    ORSet.merge(s2, state1)

    assert ORSet.members(s1) == ORSet.members(s2)
    assert ORSet.state(s1) == ORSet.state(s2)
  end