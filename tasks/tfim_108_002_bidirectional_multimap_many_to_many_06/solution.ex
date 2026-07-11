  test "full many-to-many mesh stays consistent", %{bm: bm} do
    for k <- [:a, :b], v <- [1, 2] do
      BiMultiMap.put(bm, k, v)
    end

    assert MapSet.new([1, 2]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([1, 2]) == BiMultiMap.get_by_key(bm, :b)
    assert MapSet.new([:a, :b]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([:a, :b]) == BiMultiMap.get_by_value(bm, 2)
  end