  test "a zero-duration timer stays pending until an advance call fires it" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    ref = Clock.Fake.schedule(clock, [seconds: 0], fn -> send(test, :now_due) end)
    refute_receive :now_due, 50
    assert Clock.Fake.pending(clock) == 1

    assert Clock.Fake.advance(clock, seconds: 0) == [ref]
    assert_receive :now_due
  end