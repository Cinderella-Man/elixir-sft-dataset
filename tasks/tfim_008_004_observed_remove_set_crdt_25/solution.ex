  test "merging empty state into populated set is a no-op", %{s: s} do
    ORSet.add(s, :a, :n1)
    before = ORSet.state(s)
    ORSet.merge(s, %{entries: %{}, tombstones: MapSet.new(), clock: %{}})
    assert ORSet.state(s) == before
  end