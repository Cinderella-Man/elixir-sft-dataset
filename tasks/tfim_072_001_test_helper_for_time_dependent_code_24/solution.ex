    test "the default start time is the base advance/2 moves from" do
      {:ok, clock} = Clock.Fake.start_link([])
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      assert Clock.Fake.now(clock) == ~U[2024-01-01 01:30:00Z]
    end