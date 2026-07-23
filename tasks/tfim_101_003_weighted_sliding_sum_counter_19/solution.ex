  test "cleanup runs on its own timer and keeps running after each round", %{sc: _sc} do
    {:ok, sc2} =
      SlidingSum.start_link(clock: &Clock.now/0, bucket_ms: 100, cleanup_interval_ms: 25)

    # Round one: a bucket recorded at t=0 is far outside the 24-hour retention
    # horizon once the clock jumps past it, so an unaided cleanup must drop the
    # whole key. Nothing is ever sent to the process here.
    Clock.set(0)
    SlidingSum.add(sc2, "auto", 1)
    assert SlidingSum.keys(sc2) == ["auto"]

    Clock.set(86_400_000 + 100)
    assert wait_until(fn -> SlidingSum.keys(sc2) == [] end, 1_000)

    # Round two: a fresh key recorded after the first automatic run must also be
    # collected, which can only happen if cleanup re-scheduled itself.
    SlidingSum.add(sc2, "auto2", 2)
    assert SlidingSum.keys(sc2) == ["auto2"]

    Clock.set(2 * 86_400_000 + 200)
    assert wait_until(fn -> SlidingSum.keys(sc2) == [] end, 1_000)

    GenServer.stop(sc2)
  end