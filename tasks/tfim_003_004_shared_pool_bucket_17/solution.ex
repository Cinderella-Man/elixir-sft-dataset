  test "per-key refill follows elapsed * rate / 1000 with the documented floor", %{sp: sp} do
    # Fresh bucket starts exactly full: cap 2 - 2 = 0 remaining.
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "kr0", 2, 1.0, 2)

    # cap 5: free 2 after draining 3; +1998 ms at 1.0/s = 3.998 -> floor 3.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "kr", 5, 1.0, 3)
    Clock.advance(1_998)
    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "kr", 5, 1.0)
  end