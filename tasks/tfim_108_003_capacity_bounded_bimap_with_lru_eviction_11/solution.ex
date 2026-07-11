  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = BoundedBiMap.delete(bm, :ghost)
    BoundedBiMap.put(bm, :a, 1)
    assert :ok = BoundedBiMap.delete(bm, :ghost)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
  end