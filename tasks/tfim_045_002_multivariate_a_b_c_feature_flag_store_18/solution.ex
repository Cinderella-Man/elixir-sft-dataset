  test "set_variants rejects weights summing above 100 and empty variant lists" do
    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:over, [{:a, 60}, {:b, 50}])
    end

    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:empty, [])
    end

    assert FeatureFlags.variant_for(:over, "u1") == :off
    assert FeatureFlags.variant_for(:empty, "u1") == :off
    refute FeatureFlags.enabled_for?(:over, "u1")
  end