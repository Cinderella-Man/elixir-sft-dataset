  test "merge is associative" do
    {:ok, sa} = LWWSet.start_link([])
    {:ok, sb} = LWWSet.start_link([])
    {:ok, sc} = LWWSet.start_link([])

    LWWSet.add(sa, :a, 3)
    LWWSet.add(sb, :b, 5)
    LWWSet.remove(sb, :a, 2)
    LWWSet.add(sc, :c, 7)
    LWWSet.remove(sc, :b, 1)

    sta = LWWSet.state(sa)
    stb = LWWSet.state(sb)
    stc = LWWSet.state(sc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = LWWSet.start_link([])
    LWWSet.merge(p1, sta)
    LWWSet.merge(p1, stb)
    LWWSet.merge(p1, stc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = LWWSet.start_link([])
    {:ok, temp} = LWWSet.start_link([])
    LWWSet.merge(temp, stb)
    LWWSet.merge(temp, stc)
    bc_merged = LWWSet.state(temp)
    LWWSet.merge(p2, sta)
    LWWSet.merge(p2, bc_merged)

    assert LWWSet.members(p1) == LWWSet.members(p2)
    assert LWWSet.state(p1) == LWWSet.state(p2)
  end