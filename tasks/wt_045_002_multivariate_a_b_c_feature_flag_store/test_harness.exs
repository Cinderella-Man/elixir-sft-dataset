defmodule FeatureFlagsTest do
  use ExUnit.Case, async: false

  setup do
    # Start with default options; every assertion below observes the store
    # purely through its documented public API.
    pid = start_supervised!(FeatureFlags)
    %{pid: pid}
  end

  test "unknown flag has :off variant and is not enabled" do
    assert FeatureFlags.variant_for(:nope, "u1") == :off
    refute FeatureFlags.enabled?(:nope)
    refute FeatureFlags.enabled_for?(:nope, "u1")
  end

  test "enable makes flag :on for everyone" do
    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled?(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :on
    assert FeatureFlags.enabled_for?(:feat, "u1")
  end

  test "disable sets :off" do
    FeatureFlags.enable(:feat)
    FeatureFlags.disable(:feat)
    assert FeatureFlags.variant_for(:feat, "u1") == :off
    refute FeatureFlags.enabled_for?(:feat, "u1")
  end

  test "variant flags are not globally enabled?" do
    FeatureFlags.set_variants(:exp, [{:a, 50}, {:b, 50}])
    refute FeatureFlags.enabled?(:exp)
  end

  test "assignment is deterministic across calls" do
    FeatureFlags.set_variants(:exp, [{:a, 34}, {:b, 33}, {:c, 33}])
    first = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    second = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert first == second
  end

  test "assignment matches the cumulative-bucket formula" do
    variants = [{:a, 50}, {:b, 30}, {:c, 20}]
    FeatureFlags.set_variants(:exp, variants)

    for i <- 1..300 do
      user = "user:#{i}"
      bucket = :erlang.phash2({:exp, user}, 100)

      expected =
        cond do
          bucket < 50 -> :a
          bucket < 80 -> :b
          true -> :c
        end

      assert FeatureFlags.variant_for(:exp, user) == expected
    end
  end

  test "distribution roughly matches weights" do
    FeatureFlags.set_variants(:exp, [{:a, 70}, {:b, 30}])
    assignments = for i <- 1..2000, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    a = Enum.count(assignments, &(&1 == :a))
    b = Enum.count(assignments, &(&1 == :b))

    assert a + b == 2000
    assert a >= 1300 and a <= 1500
    assert b >= 500 and b <= 700
  end

  test "zero-weight variant receives no users" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:z, 0}])
    assignments = for i <- 1..500, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    assert Enum.all?(assignments, &(&1 == :a))
    refute Enum.any?(assignments, &(&1 == :z))
  end

  test "set_variants rejects weights that do not sum to 100" do
    assert_raise ArgumentError, fn ->
      FeatureFlags.set_variants(:bad, [{:a, 50}, {:b, 40}])
    end
  end

  test "updating variants takes effect immediately" do
    FeatureFlags.set_variants(:exp, [{:a, 100}, {:b, 0}])
    assert FeatureFlags.variant_for(:exp, "u1") == :a
    FeatureFlags.set_variants(:exp, [{:a, 0}, {:b, 100}])
    assert FeatureFlags.variant_for(:exp, "u1") == :b
  end

  test "flags are independent" do
    FeatureFlags.enable(:x)
    FeatureFlags.set_variants(:y, [{:a, 100}])
    assert FeatureFlags.variant_for(:x, "u") == :on
    assert FeatureFlags.variant_for(:y, "u") == :a
  end

  test "concurrent reads are consistent" do
    FeatureFlags.set_variants(:exp, [{:a, 100}])
    tasks = for _ <- 1..50, do: Task.async(fn -> FeatureFlags.variant_for(:exp, "u1") end)
    assert Enum.all?(Task.await_many(tasks), &(&1 == :a))
  end
end
