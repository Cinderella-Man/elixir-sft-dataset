  test "putting the same pair twice is a no-op", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 1)

    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
  end