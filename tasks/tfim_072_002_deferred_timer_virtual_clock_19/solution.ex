  test "start_link without :initial starts at the documented default instant" do
    {:ok, clock} = Clock.Fake.start_link([])
    assert Clock.Fake.now(clock) == ~U[2024-01-01 00:00:00Z]
  end