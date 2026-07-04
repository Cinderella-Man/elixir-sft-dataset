  test "each write bumps the version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    FeatureFlags.enable_for_percentage(:f, 25)
    assert FeatureFlags.version(:f) == 3
  end