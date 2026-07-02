  test "a key may hold many values", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)
    BiMultiMap.put(bm, :a, 3)

    assert MapSet.new([1, 2, 3]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 2)
  end