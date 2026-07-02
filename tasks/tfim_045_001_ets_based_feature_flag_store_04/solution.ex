  test "disable sets the flag off for everyone" do
    FeatureFlags.enable(:my_feature)
    FeatureFlags.disable(:my_feature)
    refute FeatureFlags.enabled?(:my_feature)
  end