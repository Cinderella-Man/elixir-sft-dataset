    test ":repeat_last returns the final value forever (default)" do
      last = ~U[2024-05-05 05:05:05Z]
      {:ok, c} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z], last])

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.now(c) == last
      assert Clock.Fake.remaining(c) == 0
    end