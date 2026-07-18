  test "enable_for_percentage refuses non-integer or out-of-range percentages" do
    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, 101)
    end

    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, -1)
    end

    assert_raise FunctionClauseError, fn ->
      FeatureFlags.enable_for_percentage(:guarded, 50.0)
    end

    # No rejected call may leave a flag behind.
    refute FeatureFlags.enabled?(:guarded)
    refute FeatureFlags.enabled_for?(:guarded, "user:1")
  end