  test "stores arbitrary Elixir terms as values" do
    c = start_cache(20)
    WeightedLRUCache.put(c, :list, [1, 2, 3], 1)
    WeightedLRUCache.put(c, :map, %{a: 1}, 1)
    WeightedLRUCache.put(c, nil, nil, 1)

    assert {:ok, [1, 2, 3]} = WeightedLRUCache.get(c, :list)
    assert {:ok, %{a: 1}} = WeightedLRUCache.get(c, :map)
    assert {:ok, nil} = WeightedLRUCache.get(c, nil)
  end