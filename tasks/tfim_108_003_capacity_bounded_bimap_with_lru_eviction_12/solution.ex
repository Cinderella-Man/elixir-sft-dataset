  test "keys_by_recency orders LRU-first, MRU-last", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Touch :a to move it to MRU.
    BoundedBiMap.get_by_key(bm, :a)

    assert [:b, :c, :a] == BoundedBiMap.keys_by_recency(bm)
  end