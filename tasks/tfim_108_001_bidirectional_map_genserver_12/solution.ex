  test "after delete the freed key and value can be reused", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.delete(bm, :a)

    BiMap.put(bm, :a, 2)
    BiMap.put(bm, :b, 1)

    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :b} = BiMap.get_by_value(bm, 1)
    assert {:ok, 1} = BiMap.get_by_key(bm, :b)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end