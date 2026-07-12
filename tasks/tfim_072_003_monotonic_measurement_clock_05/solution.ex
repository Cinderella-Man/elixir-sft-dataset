    test "honours an :initial offset in milliseconds" do
      {:ok, c} = Clock.Fake.start_link(initial: 1000)
      assert Clock.Fake.monotonic(c, :millisecond) == 1000
      assert Clock.Fake.monotonic(c, :second) == 1
      assert Clock.Fake.monotonic(c, :microsecond) == 1_000_000
      assert Clock.Fake.monotonic(c, :nanosecond) == 1_000_000_000
    end