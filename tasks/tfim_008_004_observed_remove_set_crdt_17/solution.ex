  test "merge applies remote tombstones to local entries", %{s: s} do
    ORSet.add(s, :x, :local)
    local_state = ORSet.state(s)
    local_tag = local_state.entries[:x] |> MapSet.to_list() |> hd()

    # Remote has tombstoned that exact tag
    remote = %{
      entries: %{},
      tombstones: MapSet.new([local_tag]),
      clock: %{}
    }

    ORSet.merge(s, remote)
    assert ORSet.member?(s, :x) == false
  end