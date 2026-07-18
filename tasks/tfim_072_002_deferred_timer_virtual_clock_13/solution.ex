    test "dispatches to Clock.Fake when given a pid" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: target)
      assert Clock.now(pid) == target
    end