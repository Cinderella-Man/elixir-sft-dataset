  test "50% rollout enables roughly half of users" do
    FeatureFlags.enable_for_percentage(:rollout, 50)

    enabled_count =
      for i <- 1..1_000 do
        FeatureFlags.enabled_for?(:rollout, "user:#{i}")
      end
      |> Enum.count(& &1)

    # Deterministic hash — we just verify it's in a sensible range
    assert enabled_count >= 400
    assert enabled_count <= 600
  end