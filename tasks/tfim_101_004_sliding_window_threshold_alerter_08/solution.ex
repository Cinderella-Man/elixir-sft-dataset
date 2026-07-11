  test "keys are tracked independently", %{sc: sc} do
    for _ <- 1..3, do: SlidingAlerter.record(sc, "a")
    SlidingAlerter.record(sc, "b")

    assert :alarm = SlidingAlerter.status(sc, "a")
    assert :ok = SlidingAlerter.status(sc, "b")
  end