  test "rollback reverts to the previous state as a new version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    assert :ok = FeatureFlags.rollback(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 3

    assert FeatureFlags.history(:f) == [
             {1, {:on}},
             {2, {:off}},
             {3, {:on}}
           ]
  end