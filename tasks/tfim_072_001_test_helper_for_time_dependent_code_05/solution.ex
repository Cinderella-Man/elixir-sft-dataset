    test "now/1 is stable — same value on repeated calls", %{clock: clock, initial: initial} do
      assert Clock.Fake.now(clock) == initial
      assert Clock.Fake.now(clock) == initial
    end