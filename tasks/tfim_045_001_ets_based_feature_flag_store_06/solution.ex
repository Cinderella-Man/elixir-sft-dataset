  test "enabled_for? returns false when flag is :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    refute FeatureFlags.enabled_for?(:feat, "user:99")
  end