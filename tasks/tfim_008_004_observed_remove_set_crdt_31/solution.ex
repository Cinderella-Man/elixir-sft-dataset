  test "re-add after merged tombstones is unaffected by previous tombstones", %{s: s} do
    # Bring in tombstones for node_a's counters 1 and 2, plus a clock recording them.
    remote = %{
      entries: %{},
      tombstones: MapSet.new([{:node_a, 1}, {:node_a, 2}]),
      clock: %{node_a: 2}
    }

    assert :ok = ORSet.merge(s, remote)

    # A fresh add from the same node must not reuse a tombstoned tag.
    ORSet.add(s, :x, :node_a)
    assert ORSet.member?(s, :x) == true

    state = ORSet.state(s)
    live_tag = state.entries[:x] |> MapSet.to_list() |> hd()
    refute MapSet.member?(state.tombstones, live_tag)
  end