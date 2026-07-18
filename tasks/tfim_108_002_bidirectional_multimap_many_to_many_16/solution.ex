  test "delete_value removes the value and cleans every forward entry", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :b, 1)
    BiMultiMap.put(bm, :a, 2)

    assert :ok = BiMultiMap.delete_value(bm, 1)

    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([2]) == BiMultiMap.get_by_key(bm, :a)
    # :b only had value 1, so it's now empty
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :b)
  end