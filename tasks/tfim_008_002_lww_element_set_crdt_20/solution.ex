  test "merge is idempotent", %{s: s} do
    LWWSet.add(s, :a, 3)
    remote = %{adds: %{a: 5, b: 2}, removes: %{a: 1}}

    LWWSet.merge(s, remote)
    members_after_first = LWWSet.members(s)
    state_after_first = LWWSet.state(s)

    LWWSet.merge(s, remote)
    members_after_second = LWWSet.members(s)
    state_after_second = LWWSet.state(s)

    assert members_after_first == members_after_second
    assert state_after_first == state_after_second
  end