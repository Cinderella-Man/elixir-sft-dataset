  test "sub-millisecond key shortage still reports a 1 ms retry_after", %{sp: sp} do
    # cap 1, rate 2000/s: drain the single token, leaving free 0.
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "fast", 1, 2000.0, 1)

    # Deficit 1 at 2000 tokens/s needs 0.5 ms — sub-millisecond — must floor up to 1.
    assert {:error, :key_empty, 1} = SharedPoolBucket.acquire(sp, "fast", 1, 2000.0, 1)
  end