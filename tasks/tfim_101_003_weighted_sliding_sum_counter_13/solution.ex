  test "active keys survive cleanup", %{sc: sc} do
    SlidingSum.add(sc, "active", 42)
    send(sc, :cleanup)

    # The sum/3 call is processed after :cleanup, acting as a barrier, and the
    # active key must still be present.
    assert 42 == SlidingSum.sum(sc, "active", 60_000)
    assert SlidingSum.keys(sc) == ["active"]
  end