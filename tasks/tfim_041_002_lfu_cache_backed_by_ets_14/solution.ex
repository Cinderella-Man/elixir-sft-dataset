  test "a get bumps frequency by exactly one, so a twice-read key outranks a once-read key" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two gets)
    LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
    assert {:ok, 1} = LFUCache.get(c, :a)

    # :b reaches frequency 2 (insert + one get) and is the most recently used
    LFUCache.put(c, :b, 2)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end