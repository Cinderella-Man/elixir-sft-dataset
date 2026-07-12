    test "now/1 returns the frozen datetime", %{clock: clock, initial: initial} do
      assert Clock.Fake.now(clock) == initial
    end