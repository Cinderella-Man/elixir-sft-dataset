  test "variant flags are not globally enabled?" do
    FeatureFlags.set_variants(:exp, [{:a, 50}, {:b, 50}])
    refute FeatureFlags.enabled?(:exp)
  end