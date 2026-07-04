  test "disable sets :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :off
    refute FeatureFlags.enabled_for?(:feat, "u1")
  end