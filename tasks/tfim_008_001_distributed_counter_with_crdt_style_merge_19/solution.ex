  test "merge is associative" do
    # Three separate counter states
    {:ok, ca} = Counter.start_link([])
    {:ok, cb} = Counter.start_link([])
    {:ok, cc} = Counter.start_link([])

    Counter.increment(ca, :a, 3)
    Counter.increment(cb, :b, 5)
    Counter.decrement(cb, :a, 2)
    Counter.increment(cc, :c, 7)
    Counter.decrement(cc, :b, 1)

    sa = Counter.state(ca)
    sb = Counter.state(cb)
    sc = Counter.state(cc)

    # Path 1: merge(merge(A, B), C)
    {:ok, p1} = Counter.start_link([])
    Counter.merge(p1, sa)
    Counter.merge(p1, sb)
    Counter.merge(p1, sc)

    # Path 2: merge(A, merge(B, C))
    {:ok, p2} = Counter.start_link([])
    {:ok, temp} = Counter.start_link([])
    Counter.merge(temp, sb)
    Counter.merge(temp, sc)
    bc_merged = Counter.state(temp)
    Counter.merge(p2, sa)
    Counter.merge(p2, bc_merged)

    assert Counter.value(p1) == Counter.value(p2)
    assert Counter.state(p1) == Counter.state(p2)
  end