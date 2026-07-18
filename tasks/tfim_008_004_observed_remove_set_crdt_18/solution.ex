  test "merge does not remove entries with tags not in tombstones", %{s: s} do
    ORSet.add(s, :x, :local)

    # Remote tombstones a different tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([{:other_node, 999}]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == true
  end