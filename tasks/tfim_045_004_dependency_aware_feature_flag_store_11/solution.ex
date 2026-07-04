  test "concurrent reads are consistent" do
    FeatureFlags.enable(:p)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:c, [:p])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enabled?(:c) end)
    assert Enum.all?(Task.await_many(tasks), & &1)
  end