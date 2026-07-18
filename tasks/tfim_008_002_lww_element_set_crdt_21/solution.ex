  test "merge is commutative" do
    {:ok, s1} = LWWSet.start_link([])
    {:ok, s2} = LWWSet.start_link([])

    # Node 1 operations
    LWWSet.add(s1, :x, 5)
    LWWSet.remove(s1, :x, 2)
    LWWSet.add(s1, :y, 1)

    # Node 2 operations
    LWWSet.add(s2, :y, 8)
    LWWSet.remove(s2, :y, 3)
    LWWSet.add(s2, :x, 2)

    state1 = LWWSet.state(s1)
    state2 = LWWSet.state(s2)

    # Merge state2 into s1
    LWWSet.merge(s1, state2)

    # Merge state1 into s2
    LWWSet.merge(s2, state1)

    # Both should converge to the same members and state
    assert LWWSet.members(s1) == LWWSet.members(s2)
    assert LWWSet.state(s1) == LWWSet.state(s2)
  end