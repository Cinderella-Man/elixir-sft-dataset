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
end