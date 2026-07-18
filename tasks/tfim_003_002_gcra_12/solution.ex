  test "works with fractional rates (e.g. 0.5 req/sec)", %{gl: gl} do
    # 0.5 req/sec → emission_interval = 2000ms, burst of 2
    assert {:ok, 1} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "slow", 0.5, 2)

    # After 2 seconds, one more is admitted
    Clock.advance(2_000)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
  end