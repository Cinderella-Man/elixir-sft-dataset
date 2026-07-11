  test "a value may be shared by many keys without evicting", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :b, 1)
    BiMultiMap.put(bm, :c, 1)

    # Unlike the bijective BiMap, the earlier keys survive.
    assert MapSet.new([:a, :b, :c]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :b)
  end