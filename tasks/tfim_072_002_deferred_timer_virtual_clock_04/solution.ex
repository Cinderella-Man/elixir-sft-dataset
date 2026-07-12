    test "advance moves virtual time forward", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 90 * 60, :second)
    end