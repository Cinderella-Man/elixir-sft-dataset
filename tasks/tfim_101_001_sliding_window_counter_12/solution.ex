  test "active keys survive cleanup", %{sc: sc} do
    SlidingCounter.increment(sc, "active")

    send(sc, :cleanup)

    # The synchronous count runs after the :cleanup message has been handled,
    # and the fresh event is still inside the retention horizon.
    assert 1 = SlidingCounter.count(sc, "active", 60_000)
  end