  test "merging empty state into populated set is a no-op", %{s: s} do
    LWWSet.add(s, :a, 5)
    before = LWWSet.state(s)
    LWWSet.merge(s, %{adds: %{}, removes: %{}})
    assert LWWSet.state(s) == before
  end