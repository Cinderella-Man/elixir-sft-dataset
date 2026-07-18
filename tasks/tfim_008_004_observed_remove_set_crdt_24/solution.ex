  test "repeated merges after continued operations converge" do
    {:ok, n1} = ORSet.start_link([])
    {:ok, n2} = ORSet.start_link([])

    # Round 1
    ORSet.add(n1, :a, :n1)
    ORSet.add(n2, :b, :n2)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)
    assert ORSet.members(n1) == MapSet.new([:a, :b])
    assert ORSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: n1 adds :c, n2 removes :a
    ORSet.add(n1, :c, :n1)
    ORSet.remove(n2, :a)

    s1 = ORSet.state(n1)
    s2 = ORSet.state(n2)
    ORSet.merge(n1, s2)
    ORSet.merge(n2, s1)

    # :a removed, :b and :c remain
    assert ORSet.members(n1) == MapSet.new([:b, :c])
    assert ORSet.members(n2) == MapSet.new([:b, :c])
  end