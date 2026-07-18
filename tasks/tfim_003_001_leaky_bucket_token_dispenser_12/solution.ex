  test "retry_after accounts for multi-token request", %{lb: lb} do
    # Capacity 10, refill 2/sec. Drain all.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 2)

    # Need 4 tokens at 2/sec => 2000ms
    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 10, 2, 4)

    assert retry_after >= 1_800 and retry_after <= 2_200
  end