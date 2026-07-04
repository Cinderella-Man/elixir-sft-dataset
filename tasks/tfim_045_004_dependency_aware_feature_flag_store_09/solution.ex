  test "self-dependency is rejected" do
    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:x, [:x])
  end