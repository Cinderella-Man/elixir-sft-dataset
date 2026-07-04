  test "flags maintain independent histories" do
    FeatureFlags.enable(:a)
    FeatureFlags.disable(:b)
    FeatureFlags.disable(:a)
    assert FeatureFlags.version(:a) == 2
    assert FeatureFlags.version(:b) == 1
    assert FeatureFlags.history(:b) == [{1, {:off}}]
  end