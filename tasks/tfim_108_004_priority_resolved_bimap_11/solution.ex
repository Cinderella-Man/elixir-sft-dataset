  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
  end