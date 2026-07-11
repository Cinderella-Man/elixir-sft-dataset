  test "delete removes just one association in both directions", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)

    assert :ok = BiMultiMap.delete(bm, :a, 1)

    refute BiMultiMap.member?(bm, :a, 1)
    assert BiMultiMap.member?(bm, :a, 2)
    assert MapSet.new([2]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
  end