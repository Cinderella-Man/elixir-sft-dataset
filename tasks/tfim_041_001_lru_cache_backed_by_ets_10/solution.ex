  test "updating an existing key refreshes its recency" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Update :a — it should now be MRU; :b becomes LRU
    LRUCache.put(c, :a, 99)

    # should evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end