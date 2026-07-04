  test "unknown flag defaults" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.version(:nope) == 0
    assert FeatureFlags.history(:nope) == []
  end