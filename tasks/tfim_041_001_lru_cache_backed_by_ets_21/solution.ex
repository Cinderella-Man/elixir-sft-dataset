  test "overwriting a key at exactly max_size evicts nothing" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Cache is exactly at max_size; overwriting a resident key must not evict.
    assert :ok = LRUCache.put(c, :b, 22)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 22} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end