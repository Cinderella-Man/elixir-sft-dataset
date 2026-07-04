  test "dependent flag is disabled until its prerequisite is enabled" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    refute FeatureFlags.enabled?(:child)
    FeatureFlags.enable(:parent)
    assert FeatureFlags.enabled?(:child)
    FeatureFlags.disable(:parent)
    refute FeatureFlags.enabled?(:child)
  end