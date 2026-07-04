  test "stores various Elixir terms as values", %{cache: cache} do
    TTLCache.put(cache, "int", 42, 1_000)
    TTLCache.put(cache, "list", [1, 2, 3], 1_000)
    TTLCache.put(cache, "map", %{a: 1}, 1_000)
    TTLCache.put(cache, "tuple", {:ok, "yes"}, 1_000)

    assert {:ok, 42} = TTLCache.get(cache, "int")
    assert {:ok, [1, 2, 3]} = TTLCache.get(cache, "list")
    assert {:ok, %{a: 1}} = TTLCache.get(cache, "map")
    assert {:ok, {:ok, "yes"}} = TTLCache.get(cache, "tuple")
  end