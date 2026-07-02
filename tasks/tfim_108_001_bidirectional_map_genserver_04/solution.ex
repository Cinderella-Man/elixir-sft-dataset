  test "multiple independent pairs coexist", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 2)
    BiMap.put(bm, :c, 3)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, 2} = BiMap.get_by_key(bm, :b)
    assert {:ok, 3} = BiMap.get_by_key(bm, :c)

    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
    assert {:ok, :b} = BiMap.get_by_value(bm, 2)
    assert {:ok, :c} = BiMap.get_by_value(bm, 3)
  end