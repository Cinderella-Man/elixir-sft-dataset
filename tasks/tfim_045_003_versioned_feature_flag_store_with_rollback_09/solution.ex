  test "rollback fails when there is no previous version" do
    FeatureFlags.enable(:f)
    assert {:error, :no_previous_version} = FeatureFlags.rollback(:f)
  end