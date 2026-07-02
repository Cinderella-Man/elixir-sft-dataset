  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nonexistent)
    refute FeatureFlags.enabled_for?(:nonexistent, "user:1")
  end