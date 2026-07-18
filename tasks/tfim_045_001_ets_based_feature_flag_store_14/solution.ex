  test "updating percentage takes effect immediately" do
    FeatureFlags.enable_for_percentage(:staged, 0)
    refute FeatureFlags.enabled_for?(:staged, "user:1")

    FeatureFlags.enable_for_percentage(:staged, 100)
    assert FeatureFlags.enabled_for?(:staged, "user:1")
  end