  test "deleting an absent association is a harmless no-op", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    assert :ok = BiMultiMap.delete(bm, :a, 999)
    assert :ok = BiMultiMap.delete(bm, :ghost, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
  end