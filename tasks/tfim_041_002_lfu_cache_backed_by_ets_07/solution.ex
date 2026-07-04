  test "put-update counts as an access and raises frequency" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # updating :a bumps its frequency to 2
    LFUCache.put(c, :a, 11)
    LFUCache.put(c, :b, 2)

    # :b has frequency 1, :a has frequency 2 → evict :b
    LFUCache.put(c, :c, 3)

    assert {:ok, 11} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end