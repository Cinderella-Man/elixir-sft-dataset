  test "enable then read at version 1" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 1
  end