  test "set_variants rejects weights that do not sum to 100" do
    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:bad, [{:a, 50}, {:b, 40}])
    end
  end