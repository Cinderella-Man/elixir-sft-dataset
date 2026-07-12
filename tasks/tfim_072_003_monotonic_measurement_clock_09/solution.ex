    test "monotonic is never decreasing across advances" do
      {:ok, c} = Clock.Fake.start_link([])
      t0 = Clock.Fake.monotonic(c, :microsecond)
      Clock.Fake.advance(c, microseconds: 5)
      t1 = Clock.Fake.monotonic(c, :microsecond)
      assert t1 >= t0
    end