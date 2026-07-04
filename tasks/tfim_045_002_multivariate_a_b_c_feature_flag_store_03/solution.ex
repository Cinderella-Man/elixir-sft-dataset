  test "enable makes flag :on for everyone" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled?(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :on
    assert FeatureFlags.enabled_for?(:feat, "u1")
  end