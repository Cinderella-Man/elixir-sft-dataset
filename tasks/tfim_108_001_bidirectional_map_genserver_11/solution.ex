  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = BiMap.delete(bm, :ghost)
    assert :error = BiMap.get_by_key(bm, :ghost)

    # Other entries are untouched
    BiMap.put(bm, :a, 1)
    assert :ok = BiMap.delete(bm, :ghost)
    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
  end