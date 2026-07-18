  test "retry_after for :key_empty is ceil(deficit * 1000 / rate), exactly", %{sp: sp} do
    # cap 2, rate 2.0: drain 1 -> free 1; asking for 2 leaves deficit 1.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "ra1", 2, 2.0, 1)
    assert {:error, :key_empty, 500} = SharedPoolBucket.acquire(sp, "ra1", 2, 2.0, 2)

    # Non-integer quotient rounds UP: deficit 1 at 3.0 tokens/s -> 334 ms.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "ra2", 1, 3.0, 1)
    assert {:error, :key_empty, 334} = SharedPoolBucket.acquire(sp, "ra2", 1, 3.0, 1)
  end