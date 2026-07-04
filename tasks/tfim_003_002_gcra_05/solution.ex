  test "long idle does not credit the bucket beyond burst size", %{gl: gl} do
    # Consume a few, then idle for a very long time.
    for _ <- 1..3, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    Clock.advance(10_000_000)

    # We should admit exactly `burst` requests back-to-back — the million
    # milliseconds of idle time must not translate to a million-request burst.
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end