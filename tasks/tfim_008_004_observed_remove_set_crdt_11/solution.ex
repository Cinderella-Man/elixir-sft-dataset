  test "clock increments per node", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_a)
    ORSet.add(s, :z, :node_b)

    state = ORSet.state(s)
    assert state.clock[:node_a] == 2
    assert state.clock[:node_b] == 1
  end