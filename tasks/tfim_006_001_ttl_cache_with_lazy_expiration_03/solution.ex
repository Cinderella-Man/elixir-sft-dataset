  test "put then get returns the stored value", %{cache: cache} do
    assert :ok = TTLCache.put(cache, "k", "hello", 1_000)
    assert {:ok, "hello"} = TTLCache.get(cache, "k")
  end