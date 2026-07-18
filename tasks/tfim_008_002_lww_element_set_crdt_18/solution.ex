  test "merge introduces new elements from remote", %{s: s} do
    LWWSet.add(s, :a, 1)
    remote = %{adds: %{b: 5, c: 3}, removes: %{c: 2}}
    LWWSet.merge(s, remote)

    assert LWWSet.members(s) == MapSet.new([:a, :b, :c])
  end