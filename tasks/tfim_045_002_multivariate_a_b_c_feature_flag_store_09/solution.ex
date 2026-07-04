  test "zero-weight variant receives no users" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:z, 0}])
    assignments = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert Enum.all?(assignments, &(&1 == :a))
    refute Enum.any?(assignments, &(&1 == :z))
  end