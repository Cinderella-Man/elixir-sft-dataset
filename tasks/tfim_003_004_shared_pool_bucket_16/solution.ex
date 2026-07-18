  test "global refill follows elapsed * rate / 1000 with the documented floor", %{sp: sp} do
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "gr", 100, 100.0, 6)

    # 4 free + 1998 ms * 1.0/s = 5.998 -> floor 5 (a /1000 or arithmetic slip
    # lands on 6 or refills to capacity).
    Clock.advance(1_998)
    assert {:ok, 5} = SharedPoolBucket.global_level(sp)
  end