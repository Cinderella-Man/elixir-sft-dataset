  test "removing the last value prunes the key entirely", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.delete(bm, :a, 1)

    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
  end