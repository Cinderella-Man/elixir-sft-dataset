    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _} = Clock.Fake.start_link(script: [target], name: :v3_named_clock)
      assert Clock.now(:v3_named_clock) == target
    end