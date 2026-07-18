  test "set_variants rejects a negative weight even when the weights total 100" do
    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:neg, [{:a, -10}, {:b, 110}])
    end

    assert FeatureFlags.variant_for(:neg, "u1") == :off
  end