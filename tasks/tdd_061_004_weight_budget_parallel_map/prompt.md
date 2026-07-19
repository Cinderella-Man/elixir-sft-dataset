# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule WeightedMapTest do
  use ExUnit.Case, async: false

  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "empty collection returns []" do
    assert [] = WeightedMap.pmap([], fn x -> x end, fn _ -> 1 end, 5)
  end

  test "returns results in original order" do
    input = Enum.to_list(1..10)
    results = WeightedMap.pmap(input, fn x -> x * 10 end, fn _ -> 1 end, 3)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "weighted elements are mapped in order" do
    input = [3, 5, 2, 4, 6, 1]
    results = WeightedMap.pmap(input, fn x -> x * 10 end, & &1, 8)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "order preserved when tasks finish out of order" do
    results =
      WeightedMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        fn _ -> 1 end,
        6
      )

    assert results == Enum.to_list(1..6)
  end

  # -------------------------------------------------------
  # Weight budget enforcement
  # -------------------------------------------------------

  test "never exceeds the weight budget" do
    {:ok, meter} = WeightMeter.start_link([])

    input = [3, 5, 2, 4, 6, 1, 3, 2]

    WeightedMap.pmap(
      input,
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      8
    )

    assert WeightMeter.peak(meter) <= 8
  end

  test "a task heavier than the budget runs alone" do
    {:ok, meter} = WeightMeter.start_link([])

    # weight 10 > budget 4: it must run by itself, so the peak is exactly 10.
    WeightedMap.pmap(
      [10, 1],
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      4
    )

    assert WeightMeter.peak(meter) == 10
  end

  test "runs several small tasks in parallel under the budget" do
    {:ok, meter} = WeightMeter.start_link([])

    WeightedMap.pmap(
      List.duplicate(1, 6),
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 80)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      3
    )

    assert WeightMeter.peak(meter) >= 2
    assert WeightMeter.peak(meter) <= 3
  end

  # -------------------------------------------------------
  # Crash handling
  # -------------------------------------------------------

  test "a crashing function returns {:error, reason} for that element only" do
    results =
      WeightedMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "boom"
          x -> x * 10
        end,
        fn _ -> 1 end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end

  test "a crash releases weight so remaining work still proceeds" do
    results =
      WeightedMap.pmap(
        [5, 5, 5],
        fn
          x -> if x == 5, do: x
        end,
        & &1,
        5
      )

    # All weights equal budget, so they run one at a time; each returns its value.
    assert results == [5, 5, 5]
  end

  test "invalid weight raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn _ -> 0 end, 5)
    end
  end

  # -------------------------------------------------------
  # WeightMeter unit tests
  # -------------------------------------------------------

  describe "WeightMeter" do
    test "tracks running total and peak" do
      {:ok, m} = WeightMeter.start_link([])
      assert WeightMeter.peak(m) == 0
      assert WeightMeter.add(m, 3) == 3
      assert WeightMeter.add(m, 4) == 7
      assert WeightMeter.sub(m, 5) == 2
      assert WeightMeter.peak(m) == 7
    end
  end

  test "weight of a raising element is released so later queued work still runs" do
    results =
      WeightedMap.pmap(
        [4, 1, 1],
        fn
          4 -> raise "boom"
          x -> x * 100
        end,
        & &1,
        4
      )

    assert match?({:error, _}, Enum.at(results, 0))
    assert Enum.drop(results, 1) == [100, 100]
  end

  test "an oversize element waits until every running element has finished" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [1, 10],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x
            end
          end,
          & &1,
          4
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 1, p1}, 1_000
    refute_receive {:started, 10, _}, 200
    send(p1, :go)
    assert_receive {:started, 10, p10}, 1_000
    send(p10, :go)
    assert_receive {:results, [1, 10]}, 1_000
  end

  test "a light element does not jump ahead of a blocked heavier queue head" do
    parent = self()

    spawn_link(fn ->
      results =
        WeightedMap.pmap(
          [2, 3, 1],
          fn x ->
            send(parent, {:started, x, self()})

            receive do
              :go -> x * 10
            end
          end,
          & &1,
          3
        )

      send(parent, {:results, results})
    end)

    assert_receive {:started, 2, p2}, 1_000
    refute_receive {:started, 1, _}, 200
    send(p2, :go)
    assert_receive {:started, 3, p3}, 1_000
    send(p3, :go)
    assert_receive {:started, 1, p1}, 1_000
    send(p1, :go)
    assert_receive {:results, [20, 30, 10]}, 1_000
  end

  test "a task killed abnormally yields an error tuple and leaves the others intact" do
    results =
      WeightedMap.pmap(
        [1, 2, 3],
        fn
          2 -> Process.exit(self(), :kill)
          x -> x * 10
        end,
        fn _ -> 1 end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert Enum.at(results, 1) == {:error, :killed}
    assert Enum.at(results, 2) == 30
  end

  test "float, negative and non-numeric weights all raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> 1.5 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> -2 end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1], fn x -> x end, fn _ -> :heavy end, 5)
    end

    assert_raise ArgumentError, fn ->
      WeightedMap.pmap([1, 2], fn x -> x end, fn x -> x - 1 end, 5)
    end
  end

  test "WeightMeter can be reached through a registered :name" do
    {:ok, pid} = WeightMeter.start_link(name: :audit_weight_meter)

    assert Process.whereis(:audit_weight_meter) == pid
    assert WeightMeter.add(:audit_weight_meter, 4) == 4
    assert WeightMeter.add(:audit_weight_meter, 3) == 7
    assert WeightMeter.sub(:audit_weight_meter, 7) == 0
    assert WeightMeter.peak(:audit_weight_meter) == 7
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
