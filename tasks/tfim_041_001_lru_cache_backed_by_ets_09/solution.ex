  test "repeated gets keep pushing an entry to MRU position" do
    c = start_cache(3)
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Keep touching :a
    LRUCache.get(c, :a)
    LRUCache.get(c, :a)

    # evicts :b (oldest untouched)
    LRUCache.put(c, :d, 4)
    # evicts :c
    LRUCache.put(c, :e, 5)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end