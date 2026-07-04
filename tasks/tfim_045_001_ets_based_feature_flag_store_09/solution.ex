  test "100% lets everyone through" do
    FeatureFlags.enable_for_percentage(:feat, 100)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == true))
  end