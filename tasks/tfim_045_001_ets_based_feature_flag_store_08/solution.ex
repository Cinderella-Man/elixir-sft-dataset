  test "0% lets nobody through" do
    FeatureFlags.enable_for_percentage(:feat, 0)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == false))
  end