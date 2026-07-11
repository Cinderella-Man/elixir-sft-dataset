  test "get_by_value refreshes recency and protects a pair from eviction", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # Access :a via the value side; :b becomes the LRU.
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 1)

    BoundedBiMap.put(bm, :c, 3)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
  end