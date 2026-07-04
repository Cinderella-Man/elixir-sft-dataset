  test "enabled_for? returns true when flag is :on" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled_for?(:feat, "user:1")
    assert FeatureFlags.enabled_for?(:feat, "user:2")
  end