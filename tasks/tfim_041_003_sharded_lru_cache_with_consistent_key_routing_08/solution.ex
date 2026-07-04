  test "eviction is confined to the key's own shard" do
    c = start_cache(4, 2)
    [k1, k2, k3] = colliding_keys(c, 3)

    LRUCacheSharded.put(c, k1, :v1)
    LRUCacheSharded.put(c, k2, :v2)
    # shard capacity is 2 → inserting k3 evicts k1 (LRU) within that shard
    LRUCacheSharded.put(c, k3, :v3)

    assert :miss = LRUCacheSharded.get(c, k1)
    assert {:ok, :v2} = LRUCacheSharded.get(c, k2)
    assert {:ok, :v3} = LRUCacheSharded.get(c, k3)
  end