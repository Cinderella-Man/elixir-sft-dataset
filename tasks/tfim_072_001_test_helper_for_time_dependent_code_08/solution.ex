    test "advance by seconds moves the clock forward", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 30)
      expected = DateTime.add(initial, 30, :second)
      assert Clock.Fake.now(clock) == expected
    end