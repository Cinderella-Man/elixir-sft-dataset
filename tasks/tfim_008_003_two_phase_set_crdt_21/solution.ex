  test "two-node simulation with divergent ops then merge" do
    {:ok, node_a} = TwoPhaseSet.start_link([])
    {:ok, node_b} = TwoPhaseSet.start_link([])

    # Node A: adds users
    TwoPhaseSet.add(node_a, :alice)
    TwoPhaseSet.add(node_a, :bob)

    # Node B: adds alice too, then removes her
    TwoPhaseSet.add(node_b, :alice)
    TwoPhaseSet.add(node_b, :charlie)
    TwoPhaseSet.remove(node_b, :alice)

    # Before merge
    assert TwoPhaseSet.members(node_a) == MapSet.new([:alice, :bob])
    assert TwoPhaseSet.members(node_b) == MapSet.new([:charlie])

    # Bidirectional merge
    state_a = TwoPhaseSet.state(node_a)
    state_b = TwoPhaseSet.state(node_b)
    TwoPhaseSet.merge(node_a, state_b)
    TwoPhaseSet.merge(node_b, state_a)

    # Both converge: alice is tombstoned, bob and charlie remain
    assert TwoPhaseSet.members(node_a) == MapSet.new([:bob, :charlie])
    assert TwoPhaseSet.members(node_b) == MapSet.new([:bob, :charlie])
  end