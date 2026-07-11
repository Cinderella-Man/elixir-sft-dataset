  test "status stays in alarm while count remains at or above threshold", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "k")
    assert :alarm = SlidingAlerter.record(sc, "k")
    assert 4 = SlidingAlerter.count(sc, "k")
  end