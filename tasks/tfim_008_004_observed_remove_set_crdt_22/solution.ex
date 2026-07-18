  test "merge is associative" do
    {:ok, sa} = ORSet.start_link([])
    {:ok, sb} = ORSet.start_link([])
    {:ok, sc} = ORSet.start_link([])

    ORSet.add(sa, :a, :n1)
    ORSet.add(sb, :b, :n2)
    ORSet.add(sc, :c, :n3)
    ORSet.add(sc, :a, :n3)

    sta = ORSet.state(sa)
    stb = ORSet.state(sb)
    stc = ORSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = ORSet.start_link([])
    ORSet.merge(p1, sta)
    ORSet.merge(p1, stb)
    ORSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = ORSet.start_link([])
    {:ok, temp} = ORSet.start_link([])
    ORSet.merge(temp, stb)
    ORSet.merge(temp, stc)
    bc_merged = ORSet.state(temp)
    ORSet.merge(p2, sta)
    ORSet.merge(p2, bc_merged)

    assert ORSet.members(p1) == ORSet.members(p2)
    assert ORSet.state(p1) == ORSet.state(p2)
  end