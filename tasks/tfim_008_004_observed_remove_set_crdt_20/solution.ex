  test "merge is idempotent", %{s: s} do
    ORSet.add(s, :a, :n1)

    remote = %{
      entries: %{b: MapSet.new([{:n2, 1}])},
      tombstones: MapSet.new(),
      clock: %{n2: 1}
    }

    ORSet.merge(s, remote)
    members_first = ORSet.members(s)
    state_first = ORSet.state(s)

    ORSet.merge(s, remote)
    members_second = ORSet.members(s)
    state_second = ORSet.state(s)

    assert members_first == members_second
    assert state_first == state_second
  end