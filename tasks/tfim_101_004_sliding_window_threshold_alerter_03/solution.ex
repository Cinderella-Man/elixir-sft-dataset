  test "below threshold the status stays :ok", %{sc: sc} do
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.record(sc, "k")
    assert :ok = SlidingAlerter.status(sc, "k")
    assert 2 = SlidingAlerter.count(sc, "k")
  end