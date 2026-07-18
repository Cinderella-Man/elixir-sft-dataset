    test "greets 'evening' after advancing past 18:00" do
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 14:00:00Z])
      Clock.Fake.advance(clock, hours: 5)
      assert Greeter.greet("Carol", clock: clock) == "Good evening, Carol!"
    end