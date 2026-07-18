  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Node A adds users
    ORSet.add(node_a, :alice, :a)
    ORSet.add(node_a, :bob, :a)

    # Node B adds users
    ORSet.add(node_b, :charlie, :b)
    ORSet.add(node_b, :bob, :b)

    # Before merge
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob])
    assert ORSet.members(node_b) == MapSet.new([:charlie, :bob])

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # Both converge to all users
    assert ORSet.members(node_a) == MapSet.new([:alice, :bob, :charlie])
    assert ORSet.members(node_b) == MapSet.new([:alice, :bob, :charlie])
  end