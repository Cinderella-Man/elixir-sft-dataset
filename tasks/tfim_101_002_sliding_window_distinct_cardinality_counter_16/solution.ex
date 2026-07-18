  test "active keys survive cleanup", %{sc: sc} do
    SlidingUniqueCounter.add(sc, "active", "u1")

    send(sc, :cleanup)

    # distinct_count is a synchronous call ordered after :cleanup, so this
    # both flushes the cleanup message and checks observable behavior.
    assert 1 = SlidingUniqueCounter.distinct_count(sc, "active", 60_000)
    assert SlidingUniqueCounter.tracked_key_count(sc) == 1
  end