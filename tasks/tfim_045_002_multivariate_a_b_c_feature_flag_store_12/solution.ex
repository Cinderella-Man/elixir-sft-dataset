  test "flags are independent" do
    FeatureFlags.enable(:x)
    FeatureFlags.set_variants(:y, [{:a, 100}])
    assert FeatureFlags.variant_for(:x, "u") == :on
    assert FeatureFlags.variant_for(:y, "u") == :a
  end