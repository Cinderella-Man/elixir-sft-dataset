  test "retry_after accounts for partial token balance", %{lb: lb} do
    # Capacity 5, refill 2/sec. Drain all.
    for _ <- 1..5, do: LeakyBucket.acquire(lb, "b", 5, 2)

    # Advance 200ms => 0.4 tokens refilled (not enough for 1)
    Clock.advance(200)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 2, 1)

    # Need 0.6 more tokens at 2/sec => 300ms
    assert retry_after >= 200 and retry_after <= 400
  end