  test "expired key is removed from internal state on read", %{cache: cache} do
    TTLCache.put(cache, "k", "v", 100)
    Clock.advance(200)

    # Read triggers lazy deletion
    assert :miss = TTLCache.get(cache, "k")

    # Verify internal state no longer holds the key
    state = :sys.get_state(cache)
    refute Map.has_key?(state.entries, "k")
  end