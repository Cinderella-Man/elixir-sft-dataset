    test "timers fire in chronological order regardless of registration order", %{clock: clock} do
      test = self()
      # Registered late-first, then early — firing must reorder to :b before :a.
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :a) end)
      Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :b) end)

      fired = Clock.Fake.advance(clock, seconds: 20)
      assert length(fired) == 2
      assert drain(2) == [:b, :a]
    end