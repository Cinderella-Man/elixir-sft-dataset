  test "reassigning a key to a new value removes the old reverse mapping", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    BiMap.put(bm, :a, 2)

    # Old value's reverse mapping is gone
    assert :error = BiMap.get_by_value(bm, 1)

    # Key now maps to the new value, both directions consistent
    assert {:ok, 2} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 2)
  end