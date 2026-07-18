  test "merge is associative" do
    {:ok, sa} = TwoPhaseSet.start_link([])
    {:ok, sb} = TwoPhaseSet.start_link([])
    {:ok, sc} = TwoPhaseSet.start_link([])

    TwoPhaseSet.add(sa, :a)
    TwoPhaseSet.add(sb, :b)
    TwoPhaseSet.add(sb, :a)
    TwoPhaseSet.remove(sb, :a)
    TwoPhaseSet.add(sc, :c)

    sta = TwoPhaseSet.state(sa)
    stb = TwoPhaseSet.state(sb)
    stc = TwoPhaseSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(p1, sta)
    TwoPhaseSet.merge(p1, stb)
    TwoPhaseSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = TwoPhaseSet.start_link([])
    {:ok, temp} = TwoPhaseSet.start_link([])
    TwoPhaseSet.merge(temp, stb)
    TwoPhaseSet.merge(temp, stc)
    bc_merged = TwoPhaseSet.state(temp)
    TwoPhaseSet.merge(p2, sta)
    TwoPhaseSet.merge(p2, bc_merged)

    assert TwoPhaseSet.members(p1) == TwoPhaseSet.members(p2)
    assert TwoPhaseSet.state(p1) == TwoPhaseSet.state(p2)
  end