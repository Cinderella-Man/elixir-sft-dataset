  test "each add generates a unique tag", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_a)

    state = ORSet.state(s)
    tags = state.entries[:x]
    # Two adds from same node => two distinct tags
    assert MapSet.size(tags) == 2
  end