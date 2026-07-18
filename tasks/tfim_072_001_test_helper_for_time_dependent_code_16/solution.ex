    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _pid} = Clock.Fake.start_link(initial: target, name: :my_test_clock)
      assert Clock.now(:my_test_clock) == target
    end