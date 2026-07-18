  test "arbitrary terms work as keys and values in both directions", %{bm: bm} do
    key = {:user, "abe", [1, 2]}
    value = %{tag: "v", list: [:x, {:y, 3}]}

    assert :ok = BiMultiMap.put(bm, key, value)
    assert :ok = BiMultiMap.put(bm, "string-key", value)
    assert :ok = BiMultiMap.put(bm, key, 3.5)

    assert BiMultiMap.member?(bm, key, value)
    assert MapSet.new([value, 3.5]) == BiMultiMap.get_by_key(bm, key)
    assert MapSet.new([key, "string-key"]) == BiMultiMap.get_by_value(bm, value)

    assert :ok = BiMultiMap.delete(bm, key, value)
    refute BiMultiMap.member?(bm, key, value)
    assert MapSet.new(["string-key"]) == BiMultiMap.get_by_value(bm, value)
    assert MapSet.new([3.5]) == BiMultiMap.get_by_key(bm, key)
  end