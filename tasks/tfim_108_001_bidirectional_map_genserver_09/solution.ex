  test "putting the same pair twice leaves it intact", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :a, 1)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
  end