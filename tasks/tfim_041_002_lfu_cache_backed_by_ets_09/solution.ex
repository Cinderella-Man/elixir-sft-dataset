  test "ties on frequency are broken by least recently used" do
    c = start_cache(3)
    # all three inserted at freq 1, in order :a, :b, :c
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # inserting :d evicts the LRU among the freq-1 entries → :a
    LFUCache.put(c, :d, 4)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
    assert {:ok, 4} = LFUCache.get(c, :d)
  end