  test "get returns :miss for unknown key" do
    c = start_cache(4, 10)
    assert :miss = LRUCacheSharded.get(c, :nope)
  end