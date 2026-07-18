  test "flags are independent of each other" do
    FeatureFlags.enable(:flag_a)
    FeatureFlags.disable(:flag_b)

    assert FeatureFlags.enabled?(:flag_a)
    refute FeatureFlags.enabled?(:flag_b)
  end