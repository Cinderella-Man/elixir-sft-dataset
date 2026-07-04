  test "missing key returns :miss", %{c: c} do
    assert :miss = SwrCache.get(c, :nope)
  end