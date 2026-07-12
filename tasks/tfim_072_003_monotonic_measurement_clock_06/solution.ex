    test "default unit is milliseconds" do
      {:ok, c} = Clock.Fake.start_link(initial: 42)
      assert Clock.Fake.monotonic(c) == Clock.Fake.monotonic(c, :millisecond)
    end