  test "nil and false are usable as ordinary keys and values", %{bm: bm} do
    assert :ok = BiMultiMap.put(bm, nil, false)
    assert :ok = BiMultiMap.put(bm, false, nil)

    assert BiMultiMap.member?(bm, nil, false)
    assert BiMultiMap.member?(bm, false, nil)
    assert MapSet.new([false]) == BiMultiMap.get_by_key(bm, nil)
    assert MapSet.new([nil]) == BiMultiMap.get_by_value(bm, false)

    assert :ok = BiMultiMap.delete_key(bm, nil)
    refute BiMultiMap.member?(bm, nil, false)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, false)
    # The symmetric pair {false, nil} is untouched.
    assert BiMultiMap.member?(bm, false, nil)
  end