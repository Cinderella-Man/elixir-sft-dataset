  test "put and get round-trip across shards" do
    c = start_cache(4, 10)
    for i <- 1..20, do: LRUCacheSharded.put(c, i, i * 100)

    for i <- 1..20 do
      expected = i * 100
      assert {:ok, ^expected} = LRUCacheSharded.get(c, i)
    end
  end