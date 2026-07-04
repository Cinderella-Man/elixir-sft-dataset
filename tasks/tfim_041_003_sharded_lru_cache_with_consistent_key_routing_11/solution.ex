  test "two sharded caches are fully independent" do
    c1 = start_cache(2, 4)
    c2 = start_cache(2, 4)

    LRUCacheSharded.put(c1, :k, :from_c1)
    LRUCacheSharded.put(c2, :k, :from_c2)

    assert {:ok, :from_c1} = LRUCacheSharded.get(c1, :k)
    assert {:ok, :from_c2} = LRUCacheSharded.get(c2, :k)
  end