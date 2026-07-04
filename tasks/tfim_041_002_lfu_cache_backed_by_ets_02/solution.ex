  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LFUCache.get(c, :nope)
  end