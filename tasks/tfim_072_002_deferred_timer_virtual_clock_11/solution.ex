    test "pending/1 tracks outstanding timers", %{clock: clock} do
      Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)
      Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
      assert Clock.Fake.pending(clock) == 2

      Clock.Fake.advance(clock, seconds: 5)
      assert Clock.Fake.pending(clock) == 1

      Clock.Fake.advance(clock, seconds: 10)
      assert Clock.Fake.pending(clock) == 0
    end