  test "every touch consumes exactly the next counter value" do
    c = start_cache(3)

    # New key.
    assert :ok = LRUCache.put(c, :a, 1)
    assert timestamp(c, :a) == 1

    # Another new key: the very next counter value, not a skipped one.
    assert :ok = LRUCache.put(c, :b, 2)
    assert timestamp(c, :b) == 2

    # A hit on :get is a touch and re-stamps the entry.
    assert {:ok, 1} = LRUCache.get(c, :a)
    assert timestamp(c, :a) == 3
    # ... and leaves untouched keys exactly where they were.
    assert timestamp(c, :b) == 2

    # An overwrite is a touch too.
    assert :ok = LRUCache.put(c, :b, 22)
    assert timestamp(c, :b) == 4

    # A third new key continues the same unbroken sequence.
    assert :ok = LRUCache.put(c, :c, 3)
    assert timestamp(c, :c) == 5
    assert timestamp(c, :a) == 3
  end