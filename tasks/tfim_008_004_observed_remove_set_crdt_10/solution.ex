  test "tags from different nodes are distinct", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_b)

    state = ORSet.state(s)
    tags = state.entries[:x]
    assert MapSet.size(tags) == 2
  end