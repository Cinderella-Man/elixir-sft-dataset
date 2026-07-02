  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BiMultiMap.put(bm, :a, 1)

    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
    assert BiMultiMap.member?(bm, :a, 1)
  end