  test "associations can be rebuilt after a wholesale delete", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)
    assert :ok = BiMultiMap.delete_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)

    assert :ok = BiMultiMap.put(bm, :a, 1)

    assert BiMultiMap.member?(bm, :a, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
    # The stale association dropped by delete_key must not resurrect.
    refute BiMultiMap.member?(bm, :a, 2)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 2)
  end