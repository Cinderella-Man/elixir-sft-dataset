  test "percentage rollout is deterministic — same user always gets same result" do
    FeatureFlags.enable_for_percentage(:stable, 40)

    first_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    second_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    assert first_pass == second_pass
  end