    test "advance is cumulative across multiple calls", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 10)
      Clock.Fake.advance(clock, seconds: 20)
      Clock.Fake.advance(clock, seconds: 30)
      expected = DateTime.add(initial, 60, :second)
      assert Clock.Fake.now(clock) == expected
    end