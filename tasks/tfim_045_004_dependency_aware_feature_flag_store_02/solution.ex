  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.prerequisites(:nope) == []
  end