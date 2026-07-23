    test "the default script holds under the default :repeat_last policy" do
      # With the one documented default value consumed, further reads repeat it.
      {:ok, c} = Clock.Fake.start_link([])

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
    end