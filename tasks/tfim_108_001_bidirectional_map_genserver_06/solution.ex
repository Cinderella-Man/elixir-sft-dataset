  test "putting a duplicate value under a new key evicts the old key", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :b, 1)

    # Old key is gone
    assert :error = BiMap.get_by_key(bm, :a)

    # Value now points to the new key
    assert {:ok, 1} = BiMap.get_by_key(bm, :b)
    assert {:ok, :b} = BiMap.get_by_value(bm, 1)
  end