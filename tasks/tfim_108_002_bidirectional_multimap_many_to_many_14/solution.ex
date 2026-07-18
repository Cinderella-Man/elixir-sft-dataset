  test "two instances keep entirely independent relations", %{bm: bm} do
    other = :"bimm_other_#{System.unique_integer([:positive])}"
    start_supervised!({BiMultiMap, name: other}, id: :other_bimm)

    assert :ok = BiMultiMap.put(bm, :a, 1)
    assert :ok = BiMultiMap.put(other, :a, 2)

    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([2]) == BiMultiMap.get_by_key(other, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 2)
    assert MapSet.new() == BiMultiMap.get_by_value(other, 1)
  end