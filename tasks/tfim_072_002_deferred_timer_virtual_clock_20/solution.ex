  test "advance returns fired refs chronologically rather than by registration order" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    late = Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
    early = Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)

    assert Clock.Fake.advance(clock, seconds: 20) == [early, late]
  end