  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LFUCache.put(c, :list, [1, 2, 3])
    LFUCache.put(c, :map, %{a: 1})
    LFUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LFUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LFUCache.get(c, :map)
    assert {:ok, nil} = LFUCache.get(c, nil)
  end