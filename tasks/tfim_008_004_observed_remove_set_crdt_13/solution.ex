  test "state returns the correct shape", %{s: s} do
    ORSet.add(s, :x, :node_a)
    ORSet.add(s, :y, :node_b)
    ORSet.remove(s, :x)

    state = ORSet.state(s)
    assert is_map(state)
    assert Map.has_key?(state, :entries)
    assert Map.has_key?(state, :tombstones)
    assert Map.has_key?(state, :clock)

    # :x was removed, so its entry should be gone
    refute Map.has_key?(state.entries, :x)
    # :y should still have tags
    assert MapSet.size(state.entries[:y]) == 1
    # tombstones should have the tag from :x
    assert MapSet.size(state.tombstones) == 1
  end