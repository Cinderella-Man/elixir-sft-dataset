  test "repeated merges after continued operations converge" do
    {:ok, n1} = LWWSet.start_link([])
    {:ok, n2} = LWWSet.start_link([])

    # Round 1
    LWWSet.add(n1, :a, 1)
    LWWSet.add(n2, :b, 2)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)
    assert LWWSet.members(n1) == MapSet.new([:a, :b])
    assert LWWSet.members(n2) == MapSet.new([:a, :b])

    # Round 2: more operations after merge
    LWWSet.add(n1, :c, 3)
    LWWSet.remove(n2, :a, 4)

    s1 = LWWSet.state(n1)
    s2 = LWWSet.state(n2)
    LWWSet.merge(n1, s2)
    LWWSet.merge(n2, s1)

    # :a removed at 4 > added at 1, :b present, :c present
    assert LWWSet.members(n1) == MapSet.new([:b, :c])
    assert LWWSet.members(n2) == MapSet.new([:b, :c])
  end