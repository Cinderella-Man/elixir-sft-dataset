    test "freeze/2 can move the clock backwards", %{clock: clock} do
      past = ~U[2000-01-01 00:00:00Z]
      Clock.Fake.freeze(clock, past)
      assert Clock.Fake.now(clock) == past
    end