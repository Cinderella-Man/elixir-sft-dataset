  test "timers due at the same instant fire in registration order" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    r1 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :first) end)
    r2 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :second) end)

    assert Clock.Fake.advance(clock, seconds: 5) == [r1, r2]
    assert drain(2) == [:first, :second]
  end