  test "reassigning a key orphans the old value", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :a, 2)

    assert :error = BoundedBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 2)
  end