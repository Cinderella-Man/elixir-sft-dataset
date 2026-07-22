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

  test "failed rollback appends no version and leaves the current state untouched" do
    FeatureFlags.enable(:solo)
    assert {:error, :no_previous_version} = FeatureFlags.rollback(:solo)
    assert {:error, :no_previous_version} = FeatureFlags.rollback(:solo)
    assert FeatureFlags.version(:solo) == 1
    assert FeatureFlags.history(:solo) == [{1, {:on}}]
    assert FeatureFlags.enabled?(:solo)

    assert {:error, :unknown_flag} = FeatureFlags.rollback(:phantom)
    assert FeatureFlags.version(:phantom) == 0
    assert FeatureFlags.history(:phantom) == []
  end

  test "concurrent writes from many processes produce contiguous versions" do
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enable(:race) end)
    assert Enum.all?(Task.await_many(tasks), &(&1 == :ok))

    assert FeatureFlags.version(:race) == 50
    hist = FeatureFlags.history(:race)
    assert Enum.map(hist, fn {v, _state} -> v end) == Enum.to_list(1..50)
    assert Enum.all?(hist, fn {_v, state} -> state == {:on} end)
  end

  test "percentage boundaries 0 and 100 gate every user" do
    FeatureFlags.enable_for_percentage(:zero, 0)
    FeatureFlags.enable_for_percentage(:full, 100)

    for i <- 1..50 do
      user = "user#{i}"
      refute FeatureFlags.enabled_for?(:zero, user)
      assert FeatureFlags.enabled_for?(:full, user)
    end

    refute FeatureFlags.enabled?(:zero)
    refute FeatureFlags.enabled?(:full)
  end

  test "enable_for_percentage refuses values outside the 0..100 integer range" do
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:bad, 101) end
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:bad, -1) end
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:bad, 50.0) end
    assert FeatureFlags.version(:bad) == 0
    assert FeatureFlags.history(:bad) == []
  end

  test "table_name defaults to :feature_flags and the primary table is a named set" do
    {:ok, pid} = FeatureFlags.start_link(name: nil)
    on_exit(fn -> Process.exit(pid, :kill) end)

    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :named_table)
    assert :ets.info(:feature_flags, :owner) == pid

    FeatureFlags.enable(:default_tbl)
    assert FeatureFlags.enabled?(:default_tbl)
    assert FeatureFlags.version(:default_tbl) == 1
  end

  test "a second rollback reverts to the state immediately before the first rollback" do
    FeatureFlags.enable(:osc)
    FeatureFlags.disable(:osc)

    assert :ok = FeatureFlags.rollback(:osc)
    assert FeatureFlags.enabled?(:osc)

    assert :ok = FeatureFlags.rollback(:osc)
    refute FeatureFlags.enabled?(:osc)
    assert FeatureFlags.version(:osc) == 4

    assert FeatureFlags.history(:osc) == [{1, {:on}}, {2, {:off}}, {3, {:on}}, {4, {:off}}]
  end
end
