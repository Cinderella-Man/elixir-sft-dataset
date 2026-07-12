    test "advance returns the refs of timers it fired", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 3], fn -> send(test, :ok) end)
      assert Clock.Fake.advance(clock, seconds: 5) == [ref]
    end