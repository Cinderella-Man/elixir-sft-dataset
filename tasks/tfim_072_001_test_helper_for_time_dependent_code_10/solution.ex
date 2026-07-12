    test "advance by hours", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 2)
      expected = DateTime.add(initial, 2 * 3600, :second)
      assert Clock.Fake.now(clock) == expected
    end