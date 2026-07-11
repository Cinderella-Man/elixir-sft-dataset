  test "active keys survive cleanup", %{sc: sc} do
    SlidingAlerter.record(sc, "active")
    send(sc, :cleanup)

    # The count call is handled after :cleanup, confirming the live key remains.
    assert 1 = SlidingAlerter.count(sc, "active")
  end