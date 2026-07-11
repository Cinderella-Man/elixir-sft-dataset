  test "keys and values may be arbitrary terms", %{bm: bm} do
    BiMap.put(bm, "string_key", {:tuple, "value"})
    BiMap.put(bm, {:composite, 1}, [1, 2, 3])

    assert {:ok, {:tuple, "value"}} = BiMap.get_by_key(bm, "string_key")
    assert {:ok, "string_key"} = BiMap.get_by_value(bm, {:tuple, "value"})
    assert {:ok, [1, 2, 3]} = BiMap.get_by_key(bm, {:composite, 1})
    assert {:ok, {:composite, 1}} = BiMap.get_by_value(bm, [1, 2, 3])
  end