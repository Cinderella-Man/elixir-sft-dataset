  test "value collision removes the old key and needs no LRU eviction", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # New key :c takes value 1, which currently belongs to :a.
    # :a is removed (bijection), which frees a slot; :b must survive.
    BoundedBiMap.put(bm, :c, 1)

    assert :error = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :c} = BoundedBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    assert BoundedBiMap.size(bm) == 2
  end