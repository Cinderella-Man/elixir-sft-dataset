  test "prerequisites are transitive" do
    FeatureFlags.enable(:a)
    FeatureFlags.enable(:b)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:b, [:a])
    FeatureFlags.set_prerequisites(:c, [:b])
    assert FeatureFlags.enabled?(:c)
    FeatureFlags.disable(:a)
    refute FeatureFlags.enabled?(:c)
  end