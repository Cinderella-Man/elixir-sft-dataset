  test "different keys are completely independent", %{cache: cache} do
    TTLCache.put(cache, "a", "val_a", 300)
    TTLCache.put(cache, "b", "val_b", 1_000)

    Clock.advance(400)

    assert :miss = TTLCache.get(cache, "a")
    assert {:ok, "val_b"} = TTLCache.get(cache, "b")
  end