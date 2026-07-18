  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = LWWSet.start_link([])
    {:ok, node_b} = LWWSet.start_link([])

    # Node A: adds :user1 and :user2
    LWWSet.add(node_a, :user1, 1)
    LWWSet.add(node_a, :user2, 2)

    # Node B: adds :user3, removes :user1 (seen via earlier sync)
    LWWSet.add(node_b, :user3, 3)
    LWWSet.add(node_b, :user1, 1)
    LWWSet.remove(node_b, :user1, 4)

    # Before merge, each node only sees its own ops
    assert LWWSet.members(node_a) == MapSet.new([:user1, :user2])
    assert LWWSet.members(node_b) == MapSet.new([:user3])

    # Bidirectional merge (simulating gossip)
    state_a = LWWSet.state(node_a)
    state_b = LWWSet.state(node_b)
    LWWSet.merge(node_a, state_b)
    LWWSet.merge(node_b, state_a)

    # Both converge: user1 removed (remove at 4 > add at 1), user2 and user3 present
    assert LWWSet.members(node_a) == MapSet.new([:user2, :user3])
    assert LWWSet.members(node_b) == MapSet.new([:user2, :user3])
  end