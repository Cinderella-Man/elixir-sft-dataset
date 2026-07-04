  test "enable / disable without prerequisites" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    FeatureFlags.disable(:f)
    refute FeatureFlags.enabled?(:f)
  end