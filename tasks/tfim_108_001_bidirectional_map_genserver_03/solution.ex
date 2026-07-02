  test "missing key and missing value return :error", %{bm: bm} do
    assert :error = BiMap.get_by_key(bm, :nope)
    assert :error = BiMap.get_by_value(bm, 999)
  end