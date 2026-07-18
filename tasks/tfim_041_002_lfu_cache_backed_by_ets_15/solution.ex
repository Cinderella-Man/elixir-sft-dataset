  test "a put-update bumps frequency by exactly one, so extra writes outrank fewer writes" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two updates)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 2)
    LFUCache.put(c, :a, 3)

    # :b reaches frequency 2 (insert + one update) and is the most recently used
    LFUCache.put(c, :b, 1)
    LFUCache.put(c, :b, 2)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 9)

    assert {:ok, 3} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 9} = LFUCache.get(c, :c)
  end