  test "assignment is deterministic across calls" do
    FeatureFlags.set_variants(:exp, [{:a, 34}, {:b, 33}, {:c, 33}])
    first = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    second = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert first == second
  end