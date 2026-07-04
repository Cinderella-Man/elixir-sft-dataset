  test "repeated rejects do not push future admits further away", %{gl: gl} do
    # Burn through the burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Spam rejections — TAT must not advance with each one
    for _ <- 1..50, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After exactly one emission interval (200ms), we must still be able to
    # admit one.  If the implementation naively updated TAT on every reject,
    # the admit frontier would be 50 emission intervals into the future.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end