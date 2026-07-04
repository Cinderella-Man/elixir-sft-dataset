  test "retry_after reports time until the earliest admit", %{gl: gl} do
    # Consume full burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # At t=0 the next admit is at t=200 (one emission interval)
    assert {:error, :rate_exceeded, retry_after} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after >= 1 and retry_after <= 200

    # At t=100, retry_after should be ~100
    Clock.advance(100)

    assert {:error, :rate_exceeded, retry_after_2} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after_2 >= 1 and retry_after_2 <= 100
  end