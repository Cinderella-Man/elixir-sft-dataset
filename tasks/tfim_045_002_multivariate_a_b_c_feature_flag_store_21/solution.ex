  test "enable and disable replace an existing multivariate configuration" do
    FeatureFlags.set_variants(:swap, [{:a, 100}])
    assert FeatureFlags.variant_for(:swap, "u1") == :a

    FeatureFlags.enable(:swap)
    assert FeatureFlags.enabled?(:swap)
    assert FeatureFlags.variant_for(:swap, "u1") == :on

    FeatureFlags.disable(:swap)
    refute FeatureFlags.enabled?(:swap)
    assert FeatureFlags.variant_for(:swap, "u1") == :off
    refute FeatureFlags.enabled_for?(:swap, "u1")

    FeatureFlags.set_variants(:swap, [{:b, 100}])
    refute FeatureFlags.enabled?(:swap)
    assert FeatureFlags.variant_for(:swap, "u1") == :b
  end