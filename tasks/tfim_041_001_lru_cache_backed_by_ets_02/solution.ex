  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LRUCache.get(c, :missing)
  end