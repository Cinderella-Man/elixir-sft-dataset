  test "flag transitions from :on → :percentage → :off correctly" do
    FeatureFlags.enable(:flag)
    assert FeatureFlags.enabled?(:flag)

    FeatureFlags.enable_for_percentage(:flag, 50)
    refute FeatureFlags.enabled?(:flag)

    FeatureFlags.disable(:flag)
    refute FeatureFlags.enabled_for?(:flag, "any_user")
  end