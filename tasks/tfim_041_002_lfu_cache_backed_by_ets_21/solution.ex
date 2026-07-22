  test "a miss creates nothing and disturbs no eviction state" do
    name = :"lfu_miss_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, _} = LFUCache.start_link(name: name, max_size: 2)
    data = :"#{name}_data"

    LFUCache.put(name, :a, 1)
    LFUCache.put(name, :b, 2)

    # Hammer a missing key: still :miss every time, and the documented
    # entry-count channel shows no entry was ever created for it.
    for _ <- 1..10, do: assert(:miss = LFUCache.get(name, :nope))
    assert :ets.info(data, :size) == 2

    # Frequencies were not disturbed either: one real access makes :a the
    # survivor, and inserting :c evicts :b exactly as if no miss happened.
    assert {:ok, 1} = LFUCache.get(name, :a)
    LFUCache.put(name, :c, 3)
    assert :miss = LFUCache.get(name, :b)
    assert {:ok, 1} = LFUCache.get(name, :a)
  end