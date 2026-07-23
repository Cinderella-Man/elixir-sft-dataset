    test "freezing one clock leaves its twin at its own time" do
      start = ~U[2024-01-01 00:00:00Z]
      {:ok, c1} = Clock.Fake.start_link(initial: start)
      {:ok, c2} = Clock.Fake.start_link(initial: start)

      Clock.Fake.freeze(c1, ~U[2031-05-05 05:05:05Z])

      assert Clock.Fake.now(c1) == ~U[2031-05-05 05:05:05Z]
      assert Clock.Fake.now(c2) == start
    end