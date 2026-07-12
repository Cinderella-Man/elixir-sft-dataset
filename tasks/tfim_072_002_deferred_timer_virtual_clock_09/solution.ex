    test "cancel prevents a pending timer from firing", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :should_not_fire) end)

      assert Clock.Fake.cancel(clock, ref) == :ok
      assert Clock.Fake.advance(clock, seconds: 10) == []
      refute_receive :should_not_fire, 50
    end