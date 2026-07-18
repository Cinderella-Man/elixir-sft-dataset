  test "global_empty rejection leaves the global pool balance untouched", %{sp: sp} do
    # Per-key never blocks (cap 100). Drain global from 10 down to 2.
    assert {:ok, _, 2} = SharedPoolBucket.acquire(sp, "big", 100, 100.0, 8)

    # Ask for 5 globally: per-key admits, global (2) is short -> :global_empty.
    assert {:error, :global_empty, _} = SharedPoolBucket.acquire(sp, "big2", 100, 100.0, 5)

    # Nothing drained: the global pool is still at 2 (no time advanced).
    assert {:ok, 2} = SharedPoolBucket.global_level(sp)
  end