  test "user hashing exactly to the threshold is excluded until the threshold grows" do
    target = 25

    user_id =
      Enum.find_value(1..50_000, fn i ->
        candidate = "user:#{i}"
        if :erlang.phash2({:edge, candidate}, 100) == target, do: candidate
      end)

    assert user_id, "expected some user hashing to exactly #{target} for flag :edge"

    FeatureFlags.enable_for_percentage(:edge, target)
    refute FeatureFlags.enabled_for?(:edge, user_id)

    FeatureFlags.enable_for_percentage(:edge, target + 1)
    assert FeatureFlags.enabled_for?(:edge, user_id)
  end