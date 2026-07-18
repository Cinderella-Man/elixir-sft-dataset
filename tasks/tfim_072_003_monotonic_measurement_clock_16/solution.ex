    test "default unit flows through the dispatcher" do
      {:ok, c} = Clock.Fake.start_link(initial: 7)
      assert Clock.monotonic(c) == 7
    end