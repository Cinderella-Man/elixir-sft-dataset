  test "retry_after for :global_empty reflects the global shortage, exactly", %{sp: sp} do
    # Per-key never blocks (cap 100); global 10 - 8 = 2 free, deficit 3 at
    # 1.0 tokens/s -> exactly 3000 ms.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "g1", 100, 100.0, 8)
    assert {:error, :global_empty, 3000} = SharedPoolBucket.acquire(sp, "g2", 100, 100.0, 5)
  end