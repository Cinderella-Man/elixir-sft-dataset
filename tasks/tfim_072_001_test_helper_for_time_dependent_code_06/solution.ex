    test "freeze/2 sets the clock to an arbitrary datetime", %{clock: clock} do
      target = ~U[2099-12-31 23:59:59Z]
      Clock.Fake.freeze(clock, target)
      assert Clock.Fake.now(clock) == target
    end