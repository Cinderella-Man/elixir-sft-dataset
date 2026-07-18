    test "two clocks and their timers are independent" do
      test = self()
      {:ok, a} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      {:ok, b} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

      Clock.Fake.schedule(a, [seconds: 5], fn -> send(test, :a_fired) end)
      Clock.Fake.schedule(b, [seconds: 5], fn -> send(test, :b_fired) end)

      Clock.Fake.advance(a, seconds: 10)
      assert_receive :a_fired
      refute_receive :b_fired, 50
      assert Clock.Fake.pending(b) == 1
      assert Clock.Fake.now(b) == ~U[2024-01-01 00:00:00Z]
    end