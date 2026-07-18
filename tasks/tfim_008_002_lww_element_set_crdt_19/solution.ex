  test "merge where remote remove overrides local add", %{s: s} do
    LWWSet.add(s, :a, 5)
    remote = %{adds: %{}, removes: %{a: 10}}
    LWWSet.merge(s, remote)

    assert LWWSet.member?(s, :a) == false
  end