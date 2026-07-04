  test "repeated gets protect a hot key across several evictions" do
    c = start_cache(3)
    LFUCache.put(c, :hot, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # make :hot very frequent
    for _ <- 1..5, do: LFUCache.get(c, :hot)

    # :b and :c both have freq 1; inserting :d evicts one of them (the LRU: :b)
    LFUCache.put(c, :d, 4)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 1} = LFUCache.get(c, :hot)

    # inserting :e evicts :c next; :hot still survives
    LFUCache.put(c, :e, 5)
    assert :miss = LFUCache.get(c, :c)
    assert {:ok, 1} = LFUCache.get(c, :hot)
    assert {:ok, 4} = LFUCache.get(c, :d)
    assert {:ok, 5} = LFUCache.get(c, :e)
  end