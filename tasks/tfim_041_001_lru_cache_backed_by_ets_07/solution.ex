  test "filling beyond capacity evicts in insertion order" do
    c = start_cache(2)
    LRUCache.put(c, :x, 10)
    LRUCache.put(c, :y, 20)
    # evicts :x
    LRUCache.put(c, :z, 30)
    # evicts :y
    LRUCache.put(c, :w, 40)

    assert :miss = LRUCache.get(c, :x)
    assert :miss = LRUCache.get(c, :y)
    assert {:ok, 30} = LRUCache.get(c, :z)
    assert {:ok, 40} = LRUCache.get(c, :w)
  end