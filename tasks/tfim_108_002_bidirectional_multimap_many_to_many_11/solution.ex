  test "delete_key removes the key and cleans every reverse entry", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)
    BiMultiMap.put(bm, :b, 1)

    assert :ok = BiMultiMap.delete_key(bm, :a)

    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)
    # value 1 is still held by :b, but no longer by :a
    assert MapSet.new([:b]) == BiMultiMap.get_by_value(bm, 1)
    # value 2 had only :a, so it's now empty
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 2)
  end