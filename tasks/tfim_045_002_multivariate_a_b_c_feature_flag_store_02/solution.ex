  test "unknown flag has :off variant and is not enabled" do
    assert FeatureFlags.variant_for(:nope, "u1") == :off
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u1")
  end