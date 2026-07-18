  test "advance supports singular unit names and day units" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    Clock.Fake.advance(clock, day: 1, hour: 1, minute: 1, second: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-02 01:01:01Z]

    Clock.Fake.advance(clock, days: 2, minutes: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-04 01:02:01Z]
  end