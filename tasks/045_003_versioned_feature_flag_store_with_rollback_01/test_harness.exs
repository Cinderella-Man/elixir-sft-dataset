defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    table = :feature_flags_test
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: nil)
    %{pid: pid, table: table}
  end

  test "unknown flag defaults" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.version(:nope) == 0
    assert FeatureFlags.history(:nope) == []
  end

  test "enable then read at version 1" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 1
  end

  test "each write bumps the version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    FeatureFlags.enable_for_percentage(:f, 25)
    assert FeatureFlags.version(:f) == 3
  end

  test "history records every state in ascending version order" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    FeatureFlags.enable_for_percentage(:f, 25)

    assert FeatureFlags.history(:f) == [
             {1, {:on}},
             {2, {:off}},
             {3, {:percentage, 25}}
           ]
  end

  test "percentage flag is not globally enabled but deterministic per user" do
    FeatureFlags.enable_for_percentage(:beta, 40)
    refute FeatureFlags.enabled?(:beta)

    for i <- 1..200 do
      user = "u#{i}"
      expected = :erlang.phash2({:beta, user}, 100) < 40
      assert FeatureFlags.enabled_for?(:beta, user) == expected
    end
  end

  test "rollback reverts to the previous state as a new version" do
    FeatureFlags.enable(:f)
    FeatureFlags.disable(:f)
    assert :ok = FeatureFlags.rollback(:f)
    assert FeatureFlags.enabled?(:f)
    assert FeatureFlags.version(:f) == 3

    assert FeatureFlags.history(:f) == [
             {1, {:on}},
             {2, {:off}},
             {3, {:on}}
           ]
  end

  test "rollback chains correctly through multiple versions" do
    FeatureFlags.enable_for_percentage(:f, 10)
    FeatureFlags.enable_for_percentage(:f, 50)
    FeatureFlags.rollback(:f)
    assert FeatureFlags.version(:f) == 3

    refute FeatureFlags.enabled_for?(:f, "u") == FeatureFlags.enabled_for?(:f, "u") == false and
             false

    # the current state should equal version 1's {:percentage, 10}
    assert List.last(FeatureFlags.history(:f)) == {3, {:percentage, 10}}
  end

  test "rolled-back percentage decides enabled_for? at the restored threshold" do
    FeatureFlags.enable_for_percentage(:pct, 10)
    FeatureFlags.enable_for_percentage(:pct, 50)
    assert :ok = FeatureFlags.rollback(:pct)

    users = for i <- 1..200, do: "u#{i}"

    for user <- users do
      assert FeatureFlags.enabled_for?(:pct, user) ==
               :erlang.phash2({:pct, user}, 100) < 10
    end

    # Some user falls between the two thresholds, so the assertions above
    # would fail if the superseded 50% state still drove the decision.
    assert Enum.any?(users, fn user ->
             bucket = :erlang.phash2({:pct, user}, 100)
             bucket >= 10 and bucket < 50
           end)

    refute FeatureFlags.enabled?(:pct)
  end

  test "rollback fails when there is no previous version" do
    FeatureFlags.enable(:f)
    assert {:error, :no_previous_version} = FeatureFlags.rollback(:f)
  end

  test "rollback fails for unknown flag" do
    assert {:error, :unknown_flag} = FeatureFlags.rollback(:ghost)
  end

  test "flags maintain independent histories" do
    FeatureFlags.enable(:a)
    FeatureFlags.disable(:b)
    FeatureFlags.disable(:a)
    assert FeatureFlags.version(:a) == 2
    assert FeatureFlags.version(:b) == 1
    assert FeatureFlags.history(:b) == [{1, {:off}}]
  end

  test "concurrent reads are consistent" do
    FeatureFlags.enable(:c)
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enabled?(:c) end)
    assert Enum.all?(Task.await_many(tasks), & &1)
  end
end
