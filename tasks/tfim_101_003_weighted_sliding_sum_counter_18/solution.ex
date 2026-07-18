  test "cleanup keeps a bucket exactly on the 24-hour horizon, drops older ones", %{sc: sc} do
    SlidingSum.add(sc, "old", 5)

    Clock.set(200_000)
    SlidingSum.add(sc, "old", 11)

    # now - 86_400_000 == 0: the t=0 bucket sits exactly on the horizon — kept.
    Clock.set(86_400_000)
    send(sc, :cleanup)
    assert 16 == SlidingSum.sum(sc, "old", 100_000_000)

    # 100 s later the t=0 bucket is beyond the horizon and dropped, while the
    # t=200_000 bucket (start 200_000 >= cutoff 100_000) survives.
    Clock.set(86_500_000)
    send(sc, :cleanup)
    assert 11 == SlidingSum.sum(sc, "old", 100_000_000)
  end