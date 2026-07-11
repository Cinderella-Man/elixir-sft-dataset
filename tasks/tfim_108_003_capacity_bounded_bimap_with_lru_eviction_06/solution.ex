  test "new-key insertion at capacity evicts the LRU pair", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Touch :a so it becomes most-recently-used; :b is now the LRU.
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)

    # Inserting a brand-new key at capacity evicts :b.
    BoundedBiMap.put(bm, :d, 4)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert :error = BoundedBiMap.get_by_value(bm, 2)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
    assert {:ok, 4} = BoundedBiMap.get_by_key(bm, :d)
  end