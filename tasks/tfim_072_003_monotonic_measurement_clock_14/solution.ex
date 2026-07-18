    test "dispatches to Clock.Fake when given a pid" do
      {:ok, c} = Clock.Fake.start_link(initial: 100)
      assert Clock.monotonic(c, :millisecond) == 100
    end