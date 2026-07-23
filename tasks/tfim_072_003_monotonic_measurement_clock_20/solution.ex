    test "minutes and hours advance by their full-length equivalents" do
      {:ok, c} = Clock.Fake.start_link([])

      Clock.Fake.advance(c, minutes: 2)
      assert Clock.Fake.monotonic(c, :second) == 120
      assert Clock.Fake.monotonic(c, :millisecond) == 120_000

      Clock.Fake.advance(c, hours: 1)
      assert Clock.Fake.monotonic(c, :second) == 3720
      assert Clock.Fake.monotonic(c, :millisecond) == 3_720_000
      assert Clock.Fake.monotonic(c, :microsecond) == 3_720_000_000
    end