  test "cleanup projects from the bucket's own last update at its own rate", %{sp: sp} do
    # Bucket born at t=500 with rate 3.0 — a projection using the wrong
    # elapsed origin refills it past capacity and drops it (fresh 9), and one
    # using the wrong rate arithmetic lands on floor 4 instead of 6.
    Clock.advance(500)
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "cl3", 9, 3.0, 5)

    # +700 ms at 3.0/s: 4 + 2.1 = 6.1 < 9 -> kept; key_level floors to 6.
    Clock.advance(700)
    send(sp, :cleanup)
    assert {:ok, 6} = SharedPoolBucket.key_level(sp, "cl3", 9, 3.0)
  end