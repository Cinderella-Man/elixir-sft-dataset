  test "merging a remote state into an empty set", %{s: s} do
    remote = %{adds: %{a: 5, b: 3}, removes: %{a: 1}}
    assert :ok = LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b])
    state = LWWSet.state(s)
    assert state.adds[:a] == 5
    assert state.adds[:b] == 3
    assert state.removes[:a] == 1
  end