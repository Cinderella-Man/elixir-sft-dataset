    test "advance is cumulative", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 10)
      Clock.Fake.advance(clock, seconds: 20)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 30, :second)
    end