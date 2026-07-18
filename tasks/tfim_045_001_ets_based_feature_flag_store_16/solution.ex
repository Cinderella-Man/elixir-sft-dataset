  test "concurrent reads return consistent results" do
    FeatureFlags.enable(:concurrent_flag)

    tasks =
      for _ <- 1..50 do
        Task.async(fn -> FeatureFlags.enabled?(:concurrent_flag) end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, & &1)
  end