    test "advance mixed duration", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      expected = DateTime.add(initial, 90 * 60, :second)
      assert Clock.Fake.now(clock) == expected
    end