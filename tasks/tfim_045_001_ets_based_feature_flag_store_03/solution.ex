  test "enable sets the flag on for everyone" do
    FeatureFlags.enable(:my_feature)
    assert FeatureFlags.enabled?(:my_feature)
  end