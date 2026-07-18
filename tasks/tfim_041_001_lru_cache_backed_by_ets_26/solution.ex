  test "a fresh cache starts its counter at 0, so the first write is stamped 1" do
    c = start_cache(3)

    assert :ok = LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1
  end