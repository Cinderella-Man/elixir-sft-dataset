    test "advance is cumulative and mixes units" do
      {:ok, c} = Clock.Fake.start_link([])
      Clock.Fake.advance(c, milliseconds: 250)
      Clock.Fake.advance(c, seconds: 1, milliseconds: 500)
      assert Clock.Fake.monotonic(c, :millisecond) == 1750
    end