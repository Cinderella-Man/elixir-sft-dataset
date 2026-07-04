  test "retry_after reports time until window ends", %{fw: fw} do
    # Fill window 0 at t=0
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Advance to t=300
    Clock.advance(300)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Window 0 ends at t=1000. We're at t=300, so retry_after should be 700.
    assert retry_after == 700
  end