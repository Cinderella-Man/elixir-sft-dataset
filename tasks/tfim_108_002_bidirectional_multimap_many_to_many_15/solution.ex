  test "a re-put pair still needs only one delete to disappear", %{bm: bm} do
    # Proves the relation is a set of pairs, not a multiset with refcounts.
    assert :ok = BiMultiMap.put(bm, :a, 1)
    assert :ok = BiMultiMap.put(bm, :a, 1)
    assert :ok = BiMultiMap.put(bm, :a, 1)

    assert :ok = BiMultiMap.delete(bm, :a, 1)

    refute BiMultiMap.member?(bm, :a, 1)
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
  end