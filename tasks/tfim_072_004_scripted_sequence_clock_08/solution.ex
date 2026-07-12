    test ":cycle wraps back to the start" do
      a = ~U[2024-01-01 00:00:00Z]
      b = ~U[2024-01-01 00:00:10Z]
      {:ok, c} = Clock.Fake.start_link(script: [a, b], on_exhaust: :cycle)

      assert Clock.Fake.now(c) == a
      assert Clock.Fake.now(c) == b
      assert Clock.Fake.now(c) == a
      assert Clock.Fake.now(c) == b
    end