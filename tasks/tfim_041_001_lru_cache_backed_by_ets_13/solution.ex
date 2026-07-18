  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LRUCache.put(c, :list, [1, 2, 3])
    LRUCache.put(c, :map, %{a: 1})
    LRUCache.put(c, :tuple, {:ok, "hello"})
    LRUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LRUCache.get(c, :map)
    assert {:ok, {:ok, "hello"}} = LRUCache.get(c, :tuple)
    assert {:ok, nil} = LRUCache.get(c, nil)
  end