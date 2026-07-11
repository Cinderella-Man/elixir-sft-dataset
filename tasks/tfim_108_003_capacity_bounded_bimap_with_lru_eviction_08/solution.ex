  test "overwriting an existing key does not evict another pair", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # Overwrite :a's value; count stays 2, nothing is evicted.
    BoundedBiMap.put(bm, :a, 9)

    assert BoundedBiMap.size(bm) == 2
    assert {:ok, 9} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    # The old value is orphaned by bijection maintenance.
    assert :error = BoundedBiMap.get_by_value(bm, 1)
  end