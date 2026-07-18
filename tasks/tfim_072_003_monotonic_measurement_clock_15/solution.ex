    test "dispatches to Clock.Fake when given a registered name" do
      {:ok, _} = Clock.Fake.start_link(initial: 100, name: :v2_named_clock)
      assert Clock.monotonic(:v2_named_clock, :millisecond) == 100
    end