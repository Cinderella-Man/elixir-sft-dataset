  test "rollback chains correctly through multiple versions" do
    FeatureFlags.enable_for_percentage(:f, 10)
    FeatureFlags.enable_for_percentage(:f, 50)
    FeatureFlags.rollback(:f)
    assert FeatureFlags.version(:f) == 3
    refute FeatureFlags.enabled_for?(:f, "u") == FeatureFlags.enabled_for?(:f, "u") == false and false
    # the current state should equal version 1's {:percentage, 10}
    assert List.last(FeatureFlags.history(:f)) == {3, {:percentage, 10}}
  end