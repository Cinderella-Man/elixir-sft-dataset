  test "multiple distinct keys coexist" do
    c = start_cache(5)
    for i <- 1..5, do: LFUCache.put(c, i, i * 10)

    for i <- 1..5 do
      expected = i * 10
      assert {:ok, ^expected} = LFUCache.get(c, i)
    end
  end