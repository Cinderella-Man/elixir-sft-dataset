  test "missing key and value return empty sets", %{bm: bm} do
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :nope)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 999)
    refute BiMultiMap.member?(bm, :nope, 999)
  end