  test "rollback fails for unknown flag" do
    assert {:error, :unknown_flag} = FeatureFlags.rollback(:ghost)
  end