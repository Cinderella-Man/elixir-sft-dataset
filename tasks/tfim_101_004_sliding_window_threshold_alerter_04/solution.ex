  test "reaching the threshold puts the key in alarm", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    # The third event reaches threshold 3 -> alarm.
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.status(sc, "k")
    assert 3 = SlidingAlerter.count(sc, "k")
  end