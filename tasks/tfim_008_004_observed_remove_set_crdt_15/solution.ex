  test "merging a remote state into an empty set", %{s: s} do
    # Build a remote state manually
    remote = %{
      entries: %{a: MapSet.new([{:r, 1}]), b: MapSet.new([{:r, 2}])},
      tombstones: MapSet.new(),
      clock: %{r: 2}
    }

    assert :ok = ORSet.merge(s, remote)
    assert ORSet.members(s) == MapSet.new([:a, :b])
  end