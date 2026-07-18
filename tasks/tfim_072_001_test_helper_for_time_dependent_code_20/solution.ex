    test "greets 'afternoon' when clock is frozen at 14:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 14:00:00Z])
      assert Greeter.greet("Bob", clock: clock) == "Good afternoon, Bob!"
    end