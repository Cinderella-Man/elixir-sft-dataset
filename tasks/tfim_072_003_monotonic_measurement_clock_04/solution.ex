    test "starts at zero by default" do
      {:ok, c} = Clock.Fake.start_link([])
      assert Clock.Fake.monotonic(c, :millisecond) == 0
      assert Clock.Fake.monotonic(c, :microsecond) == 0
    end