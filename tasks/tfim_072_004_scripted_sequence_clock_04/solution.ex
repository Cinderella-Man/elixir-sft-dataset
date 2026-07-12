    test "remaining/1 counts unconsumed values", %{clock: clock} do
      assert Clock.Fake.remaining(clock) == 3
      Clock.Fake.now(clock)
      assert Clock.Fake.remaining(clock) == 2
      Clock.Fake.now(clock)
      Clock.Fake.now(clock)
      assert Clock.Fake.remaining(clock) == 0
    end