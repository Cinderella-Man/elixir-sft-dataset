  test "concurrent reads are consistent" do
    FeatureFlags.set_variants(:exp, [{:a, 100}])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.variant_for(:exp, "u1") end)
    assert Enum.all?(Task.await_many(tasks), &(&1 == :a))
  end