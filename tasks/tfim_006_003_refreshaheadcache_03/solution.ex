  test "missing key returns :miss", %{c: c} do
    assert :miss = RefreshAheadCache.get(c, :nope)
  end