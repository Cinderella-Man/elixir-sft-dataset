  test "delete removes both directions", %{bm: bm} do
    BiMap.put(bm, :a, 1)
    assert :ok = BiMap.delete(bm, :a)

    assert :error = BiMap.get_by_key(bm, :a)
    assert :error = BiMap.get_by_value(bm, 1)
  end