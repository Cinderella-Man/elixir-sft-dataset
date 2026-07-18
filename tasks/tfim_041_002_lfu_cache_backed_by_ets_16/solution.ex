  test "entry count stays at max_size: updates evict nothing, a new key evicts exactly one" do
    c = start_cache(2)
    data = :"#{c}_data"

    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    assert :ets.info(data, :size) == 2

    # updating an existing key while exactly at max_size must not evict anything
    LFUCache.put(c, :a, 11)
    assert :ets.info(data, :size) == 2
    assert {:ok, 11} = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # a new key while at max_size evicts exactly one entry before inserting
    LFUCache.put(c, :c, 3)
    assert :ets.info(data, :size) == 2
    assert {:ok, 3} = LFUCache.get(c, :c)
  end