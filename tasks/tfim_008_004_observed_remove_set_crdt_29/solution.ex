  test "removing then re-adding from same node works", %{s: s} do
    ORSet.add(s, :x, :n1)
    ORSet.remove(s, :x)
    ORSet.add(s, :x, :n1)

    state = ORSet.state(s)
    # Old tag is in tombstones, new tag is in entries
    assert MapSet.size(state.tombstones) == 1
    assert MapSet.size(state.entries[:x]) == 1

    # The live tag should NOT be in tombstones
    live_tag = state.entries[:x] |> MapSet.to_list() |> hd()
    refute MapSet.member?(state.tombstones, live_tag)
  end