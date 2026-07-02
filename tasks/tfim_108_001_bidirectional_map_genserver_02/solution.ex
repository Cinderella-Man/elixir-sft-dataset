  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BiMap.put(bm, :a, 1)

    assert {:ok, 1} = BiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BiMap.get_by_value(bm, 1)
  end