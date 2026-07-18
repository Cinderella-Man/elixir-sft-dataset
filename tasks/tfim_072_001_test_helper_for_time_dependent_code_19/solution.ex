    test "greets 'morning' when clock is frozen at 09:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 09:00:00Z])
      assert Greeter.greet("Alice", clock: clock) == "Good morning, Alice!"
    end