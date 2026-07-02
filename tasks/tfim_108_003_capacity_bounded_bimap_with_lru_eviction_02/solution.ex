  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BoundedBiMap.put(bm, :a, 1)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 1)
  end