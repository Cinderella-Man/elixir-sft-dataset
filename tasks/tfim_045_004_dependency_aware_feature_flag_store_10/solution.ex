  test "setting state preserves prerequisites and vice versa" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.disable(:child)
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.set_prerequisites(:child, [:parent, :other])
    FeatureFlags.enable(:parent)
    FeatureFlags.enable(:other)
    refute FeatureFlags.enabled?(:child)

    FeatureFlags.enable(:child)
    assert FeatureFlags.enabled?(:child)
  end