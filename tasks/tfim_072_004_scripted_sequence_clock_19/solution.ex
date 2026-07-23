    test "the default script is exactly [~U[2024-01-01 00:00:00Z]]" do
      {:ok, c} = Clock.Fake.start_link([])

      # One unconsumed value before any read, and it is the documented default.
      assert Clock.Fake.remaining(c) == 1
      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert Clock.Fake.remaining(c) == 0
    end