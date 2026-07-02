  test "admits at the steady-state rate after burst is exhausted", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After one emission interval (200ms), one more is admitted.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Two more intervals → two more admits.
    Clock.advance(400)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end