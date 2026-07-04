  test "cycles are rejected and leave the graph unchanged" do
    FeatureFlags.set_prerequisites(:b, [:a])
    FeatureFlags.set_prerequisites(:c, [:b])
    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:a, [:c])
    assert FeatureFlags.prerequisites(:a) == []
  end