    test "advance by minutes", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, minutes: 5)
      expected = DateTime.add(initial, 5 * 60, :second)
      assert Clock.Fake.now(clock) == expected
    end