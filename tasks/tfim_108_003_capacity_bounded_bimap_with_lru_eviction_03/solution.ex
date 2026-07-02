  test "missing key and value return :error", %{bm: bm} do
    assert :error = BoundedBiMap.get_by_key(bm, :nope)
    assert :error = BoundedBiMap.get_by_value(bm, 999)
  end