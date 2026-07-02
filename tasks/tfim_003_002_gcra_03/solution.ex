  test "rejects once the burst is exhausted", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert {:error, :rate_exceeded, retry_after} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert is_integer(retry_after)
    assert retry_after > 0
    # At 5 req/sec, emission interval = 200ms, so we shouldn't wait more than that
    # to admit one more after a full burst at t=0.
    assert retry_after <= 200
  end