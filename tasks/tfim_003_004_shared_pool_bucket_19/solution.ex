  test "cleanup keeps a not-yet-full bucket with its projected balance intact", %{sp: sp} do
    # cap 4: free 2 after draining 2; +1998 ms at 1.0/s projects 3.998 < 4,
    # so the sweep must KEEP the bucket (a projection slip refills it to
    # capacity and drops it, making key_level report a fresh 4).
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "cl", 4, 1.0, 2)
    Clock.advance(1_998)
    send(sp, :cleanup)

    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "cl", 4, 1.0)
  end