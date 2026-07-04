  test "least frequently used entry is evicted, not least recently used" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # bump :a's frequency to 2
    assert {:ok, 1} = LFUCache.get(c, :a)
    # :b is inserted more recently than :a but has frequency 1
    LFUCache.put(c, :b, 2)

    # inserting :c evicts the LFU entry — :b (freq 1), even though it is MRU
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end