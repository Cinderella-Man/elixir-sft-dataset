  test "delete_key and delete_value on absent terms are harmless no-ops", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)

    assert :ok = BiMultiMap.delete_key(bm, :ghost)
    assert :ok = BiMultiMap.delete_value(bm, 999)

    assert BiMultiMap.member?(bm, :a, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
  end