  test "delete frees a slot so the next new key doesn't evict", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    assert :ok = BoundedBiMap.delete(bm, :a)
    assert :error = BoundedBiMap.get_by_key(bm, :a)
    assert :error = BoundedBiMap.get_by_value(bm, 1)

    BoundedBiMap.put(bm, :c, 3)

    # :b was never evicted because delete made room.
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
  end