    test "two independent Clock.Fake instances hold independent times" do
      time_a = ~U[2020-01-01 00:00:00Z]
      time_b = ~U[2099-12-31 23:59:59Z]

      {:ok, clock_a} = Clock.Fake.start_link(initial: time_a)
      {:ok, clock_b} = Clock.Fake.start_link(initial: time_b)

      assert Clock.Fake.now(clock_a) == time_a
      assert Clock.Fake.now(clock_b) == time_b

      Clock.Fake.advance(clock_a, hours: 1)

      # clock_b must be completely unaffected
      assert Clock.Fake.now(clock_b) == time_b
      assert Clock.Fake.now(clock_a) == DateTime.add(time_a, 3600, :second)
    end