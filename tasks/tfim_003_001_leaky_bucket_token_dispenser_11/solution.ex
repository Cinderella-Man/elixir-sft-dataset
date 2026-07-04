  test "retry_after tells how long until enough tokens refill", %{lb: lb} do
    # Capacity 5, refill 2/sec. Drain all.
    for _ <- 1..5, do: LeakyBucket.acquire(lb, "b", 5, 2)

    # Need 1 token at 2/sec => 500ms
    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 2, 1)

    assert retry_after >= 400 and retry_after <= 600
  end