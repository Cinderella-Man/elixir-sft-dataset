  test "updating variants takes effect immediately" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:b, 0}])
    assert FeatureFlags.variant_for(:exp, "u1") == :a
    FeatureFlags.set_variants(:exp, [{:a, 0}, {:b, 100}])
    assert FeatureFlags.variant_for(:exp, "u1") == :b
  end