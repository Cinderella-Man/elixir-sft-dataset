  test "merge unions tags and tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    remote = %{
      entries: %{x: MapSet.new([{:remote, 1}])},
      tombstones: MapSet.new(),
      clock: %{remote: 1}
    }

    ORSet.merge(s, remote)

    state = ORSet.state(s)
    # Should have both tags for :x
    assert MapSet.size(state.entries[:x]) == 2
  end