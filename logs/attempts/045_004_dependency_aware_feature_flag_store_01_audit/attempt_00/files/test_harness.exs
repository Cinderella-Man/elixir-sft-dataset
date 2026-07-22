defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    table = :feature_flags_test
    {:ok, pid} = FeatureFlags.start_link(table_name: table, name: nil)
    %{pid: pid, table: table}
  end

  test "unknown flag defaults to false" do
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u")
    assert FeatureFlags.prerequisites(:nope) == []
  end

  test "enable / disable without prerequisites" do
    FeatureFlags.enable(:f)
    assert FeatureFlags.enabled?(:f)
    FeatureFlags.disable(:f)
    refute FeatureFlags.enabled?(:f)
  end

  test "percentage evaluation is deterministic and gated by phash2" do
    FeatureFlags.enable_for_percentage(:beta, 40)
    refute FeatureFlags.enabled?(:beta)

    for i <- 1..200 do
      user = "u#{i}"
      expected = :erlang.phash2({:beta, user}, 100) < 40
      assert FeatureFlags.enabled_for?(:beta, user) == expected
    end
  end

  test "dependent flag is disabled until its prerequisite is enabled" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    refute FeatureFlags.enabled?(:child)
    FeatureFlags.enable(:parent)
    assert FeatureFlags.enabled?(:child)
    FeatureFlags.disable(:parent)
    refute FeatureFlags.enabled?(:child)
  end

  test "enabled_for? requires prerequisites for the same user" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:gate])
    FeatureFlags.enable_for_percentage(:gate, 50)

    for i <- 1..300 do
      user = "u#{i}"
      gate_open = :erlang.phash2({:gate, user}, 100) < 50
      assert FeatureFlags.enabled_for?(:child, user) == gate_open
    end
  end

  test "prerequisites are transitive" do
    FeatureFlags.enable(:a)
    FeatureFlags.enable(:b)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:b, [:a])
    FeatureFlags.set_prerequisites(:c, [:b])
    assert FeatureFlags.enabled?(:c)
    FeatureFlags.disable(:a)
    refute FeatureFlags.enabled?(:c)
  end

  test "cycles are rejected and leave the graph unchanged" do
    FeatureFlags.set_prerequisites(:b, [:a])
    FeatureFlags.set_prerequisites(:c, [:b])
    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:a, [:c])
    assert FeatureFlags.prerequisites(:a) == []
  end

  test "self-dependency is rejected" do
    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:x, [:x])
  end

  test "setting state preserves prerequisites and vice versa" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:parent])
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.disable(:child)
    assert FeatureFlags.prerequisites(:child) == [:parent]

    FeatureFlags.set_prerequisites(:child, [:parent, :other])
    FeatureFlags.enable(:parent)
    FeatureFlags.enable(:other)
    refute FeatureFlags.enabled?(:child)

    FeatureFlags.enable(:child)
    assert FeatureFlags.enabled?(:child)
  end

  test "concurrent reads are consistent" do
    FeatureFlags.enable(:p)
    FeatureFlags.enable(:c)
    FeatureFlags.set_prerequisites(:c, [:p])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.enabled?(:c) end)
    assert Enum.all?(Task.await_many(tasks), & &1)
  end

  test "enable_for_percentage guards against non-integer and out-of-range percentages" do
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:g, 101) end
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:g, -1) end
    assert_raise FunctionClauseError, fn -> FeatureFlags.enable_for_percentage(:g, 50.0) end

    refute FeatureFlags.enabled?(:g)
    refute FeatureFlags.enabled_for?(:g, "u1")
    assert FeatureFlags.prerequisites(:g) == []
  end

  test "percentage boundaries of 0 and 100 gate nobody and everybody" do
    FeatureFlags.enable_for_percentage(:none, 0)
    FeatureFlags.enable_for_percentage(:all, 100)

    for i <- 1..150 do
      user = "user#{i}"
      refute FeatureFlags.enabled_for?(:none, user)
      assert FeatureFlags.enabled_for?(:all, user)
    end

    refute FeatureFlags.enabled?(:all)
  end

  test "start_link with no options uses the default table and default registration" do
    {:ok, pid} = FeatureFlags.start_link([])

    assert Process.whereis(FeatureFlags) == pid
    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :read_concurrency) == true

    FeatureFlags.enable(:defaulted)
    assert FeatureFlags.enabled?(:defaulted)
    assert :ets.lookup(:feature_flags, :defaulted) != []
  end

  test "rejected cycle keeps existing prerequisites and own state of the target flag" do
    FeatureFlags.enable(:za)
    FeatureFlags.enable(:aa)
    FeatureFlags.enable(:bb)
    assert :ok = FeatureFlags.set_prerequisites(:aa, [:za])
    assert :ok = FeatureFlags.set_prerequisites(:bb, [:aa])
    assert FeatureFlags.enabled?(:bb)

    assert {:error, :cycle} = FeatureFlags.set_prerequisites(:aa, [:bb])

    assert FeatureFlags.prerequisites(:aa) == [:za]
    assert FeatureFlags.prerequisites(:bb) == [:aa]
    assert FeatureFlags.enabled?(:aa)
    assert FeatureFlags.enabled?(:bb)
  end

  test "setting an empty prerequisite list clears previously declared prerequisites" do
    FeatureFlags.enable(:kid)
    assert :ok = FeatureFlags.set_prerequisites(:kid, [:dad])
    refute FeatureFlags.enabled?(:kid)
    refute FeatureFlags.enabled_for?(:kid, "u1")

    assert :ok = FeatureFlags.set_prerequisites(:kid, [])
    assert FeatureFlags.prerequisites(:kid) == []
    assert FeatureFlags.enabled?(:kid)
    assert FeatureFlags.enabled_for?(:kid, "u1")
  end

  test "setting prerequisites preserves percentage mode as the flag's own state" do
    FeatureFlags.enable_for_percentage(:pct, 100)
    assert FeatureFlags.enabled_for?(:pct, "u1")

    assert :ok = FeatureFlags.set_prerequisites(:pct, [:gate2])
    refute FeatureFlags.enabled_for?(:pct, "u1")

    FeatureFlags.enable(:gate2)
    assert FeatureFlags.enabled_for?(:pct, "u1")
    refute FeatureFlags.enabled?(:pct)
  end
end
