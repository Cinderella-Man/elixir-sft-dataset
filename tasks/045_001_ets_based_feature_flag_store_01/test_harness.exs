defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    table = :feature_flags_test

    {:ok, pid} =
      FeatureFlags.start_link(
        table_name: table,
        name: nil
      )

    %{pid: pid, table: table}
  end

  # -------------------------------------------------------
  # Basic enable / disable
  # -------------------------------------------------------

  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nonexistent)
    refute FeatureFlags.enabled_for?(:nonexistent, "user:1")
  end

  test "enable sets the flag on for everyone" do
    FeatureFlags.enable(:my_feature)
    assert FeatureFlags.enabled?(:my_feature)
  end

  test "disable sets the flag off for everyone" do
    FeatureFlags.enable(:my_feature)
    FeatureFlags.disable(:my_feature)
    refute FeatureFlags.enabled?(:my_feature)
  end

  test "enabled_for? returns true when flag is :on" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled_for?(:feat, "user:1")
    assert FeatureFlags.enabled_for?(:feat, "user:2")
  end

  test "enabled_for? returns false when flag is :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    refute FeatureFlags.enabled_for?(:feat, "user:99")
  end

  # -------------------------------------------------------
  # Percentage rollout
  # -------------------------------------------------------

  test "enabled? returns false for percentage flags" do
    FeatureFlags.enable_for_percentage(:beta, 50)
    refute FeatureFlags.enabled?(:beta)
  end

  test "0% lets nobody through" do
    FeatureFlags.enable_for_percentage(:feat, 0)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == false))
  end

  test "100% lets everyone through" do
    FeatureFlags.enable_for_percentage(:feat, 100)

    results =
      for i <- 1..200 do
        FeatureFlags.enabled_for?(:feat, "user:#{i}")
      end

    assert Enum.all?(results, &(&1 == true))
  end

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

  test "percentage rollout is deterministic — same user always gets same result" do
    FeatureFlags.enable_for_percentage(:stable, 40)

    first_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    second_pass =
      for i <- 1..500, do: FeatureFlags.enabled_for?(:stable, "user:#{i}")

    assert first_pass == second_pass
  end

  test "phash2 bucketing is consistent with expected formula" do
    FeatureFlags.enable_for_percentage(:p, 10)

    for i <- 1..200 do
      result = FeatureFlags.enabled_for?(:p, "user:#{i}")
      expected = :erlang.phash2({:p, "user:#{i}"}, 100) < 10

      assert result == expected,
             "user:#{i} — got #{result}, expected #{expected}"
    end
  end

  # -------------------------------------------------------
  # Flag state transitions
  # -------------------------------------------------------

  test "flag transitions from :on → :percentage → :off correctly" do
    FeatureFlags.enable(:flag)
    assert FeatureFlags.enabled?(:flag)

    FeatureFlags.enable_for_percentage(:flag, 50)
    refute FeatureFlags.enabled?(:flag)

    FeatureFlags.disable(:flag)
    refute FeatureFlags.enabled_for?(:flag, "any_user")
  end

  test "updating percentage takes effect immediately" do
    FeatureFlags.enable_for_percentage(:staged, 0)
    refute FeatureFlags.enabled_for?(:staged, "user:1")

    FeatureFlags.enable_for_percentage(:staged, 100)
    assert FeatureFlags.enabled_for?(:staged, "user:1")
  end

  # -------------------------------------------------------
  # Multiple flags are independent
  # -------------------------------------------------------

  test "flags are independent of each other" do
    FeatureFlags.enable(:flag_a)
    FeatureFlags.disable(:flag_b)

    assert FeatureFlags.enabled?(:flag_a)
    refute FeatureFlags.enabled?(:flag_b)
  end

  # -------------------------------------------------------
  # Concurrent reads
  # -------------------------------------------------------

  test "concurrent reads return consistent results" do
    FeatureFlags.enable(:concurrent_flag)

    tasks =
      for _ <- 1..50 do
        Task.async(fn -> FeatureFlags.enabled?(:concurrent_flag) end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, & &1)
  end
end
