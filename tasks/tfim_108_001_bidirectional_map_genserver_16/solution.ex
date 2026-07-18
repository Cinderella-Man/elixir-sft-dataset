  test "bijection survives terms used as both key and value", %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, :b)
    assert :ok = BiMap.put(bm, :b, :a)

    assert {:ok, :b} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, :b)
    assert {:ok, :a} = BiMap.get_by_key(bm, :b)
    assert {:ok, :b} = BiMap.get_by_value(bm, :a)

    # Reassign :a to itself: the old value :b is orphaned as a value, but :b
    # keeps its own forward entry :b -> :a.
    assert :ok = BiMap.put(bm, :a, :a)

    assert {:ok, :a} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, :a)
    assert :error = BiMap.get_by_key(bm, :b)
    assert :error = BiMap.get_by_value(bm, :b)
  end