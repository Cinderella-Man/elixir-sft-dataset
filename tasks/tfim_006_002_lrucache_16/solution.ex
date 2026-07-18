  test "capacity of one evicts the sole entry when a new key is inserted" do
    {:ok, c} = LRUCache.start_link(capacity: 1, clock: &Clock.now/0)

    :ok = LRUCache.put(c, :a, 1)
    :ok = LRUCache.put(c, :b, 2)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert LRUCache.size(c) == 1
  end