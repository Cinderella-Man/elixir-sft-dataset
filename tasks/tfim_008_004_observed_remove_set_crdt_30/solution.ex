  test "remove moves every current tag of the element into tombstones", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :x, :node_b)

    before = ORSet.state(s)
    all_tags = before.entries[:x]
    assert MapSet.size(all_tags) == 3

    assert :ok = ORSet.remove(s, :x)
    assert ORSet.member?(s, :x) == false

    after_state = ORSet.state(s)
    assert MapSet.subset?(all_tags, after_state.tombstones)
    assert MapSet.size(after_state.tombstones) == 3
  end