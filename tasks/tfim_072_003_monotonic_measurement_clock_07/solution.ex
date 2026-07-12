    test "advance moves the counter forward and is unit-consistent" do
      {:ok, c} = Clock.Fake.start_link([])
      Clock.Fake.advance(c, seconds: 2)
      assert Clock.Fake.monotonic(c, :second) == 2
      assert Clock.Fake.monotonic(c, :millisecond) == 2000
      assert Clock.Fake.monotonic(c, :microsecond) == 2_000_000
    end