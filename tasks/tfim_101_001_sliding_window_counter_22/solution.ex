  test "stray messages neither crash the counter nor alter its counts", %{sc: sc} do
    SlidingCounter.increment(sc, "k")
    SlidingCounter.increment(sc, "k")

    send(sc, :not_cleanup)
    send(sc, {:unrelated, self(), make_ref()})
    send(sc, "a stray binary")

    # The synchronous call is the mailbox barrier: it runs after every stray
    # message above has been handled.
    assert 2 = SlidingCounter.count(sc, "k", 1_000)
    assert Process.alive?(sc)
  end