  test "an evicted key leaves no row behind and restarts at frequency 1 when re-put" do
    c = start_cache(2)
    data = :"#{c}_data"

    # :a reaches frequency 4, :b reaches frequency 3
    LFUCache.put(c, :a, 1)
    for _ <- 1..3, do: LFUCache.get(c, :a)
    LFUCache.put(c, :b, 2)
    for _ <- 1..2, do: LFUCache.get(c, :b)

    # :b is the least frequently used, so inserting :c removes its row entirely
    LFUCache.put(c, :c, 3)
    assert :ets.lookup(data, :b) == []

    # re-inserting :b does not remember the frequency it had before eviction
    LFUCache.put(c, :b, 20)
    assert [{:b, {20, 1, _seq}}] = :ets.lookup(data, :b)
  end