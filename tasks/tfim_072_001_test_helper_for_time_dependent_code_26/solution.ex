    test "repeated advances land on one clock and leave its twin frozen" do
      start = ~U[2024-01-01 00:00:00Z]
      {:ok, c1} = Clock.Fake.start_link(initial: start)
      {:ok, c2} = Clock.Fake.start_link(initial: start)

      for _ <- 1..10, do: Clock.Fake.advance(c1, seconds: 1)

      assert Clock.Fake.now(c1) == DateTime.add(start, 10, :second)
      assert Clock.Fake.now(c2) == start
      assert Clock.Fake.now(c1) != Clock.Fake.now(c2)
    end