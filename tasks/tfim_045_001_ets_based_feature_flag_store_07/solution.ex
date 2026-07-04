  test "enabled? returns false for percentage flags" do
    FeatureFlags.enable_for_percentage(:beta, 50)
    refute FeatureFlags.enabled?(:beta)
  end