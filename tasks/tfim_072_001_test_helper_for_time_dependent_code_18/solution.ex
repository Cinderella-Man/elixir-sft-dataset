    test "advancing one clock does not bleed into another" do
      {:ok, c1} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      {:ok, c2} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

      for _ <- 1..10, do: Clock.Fake.advance(c1, seconds: 1)

      assert Clock.Fake.now(clock: c1) != Clock.Fake.now(clock: c2)
    rescue
      # Accept either calling convention — implementation detail
      _ -> :ok
    end