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
      WeightedMap.pmap(1..6, fn x -> Process.sleep((7 - x) * 20); x end, fn _ -> 1 end, 6)

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
      WeightedMap.pmap([1, 2, 3], fn
        2 -> raise "boom"
        x -> x * 10
      end, fn _ -> 1 end, 3)

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end

  test "a crash releases weight so remaining work still proceeds" do
    results =
      WeightedMap.pmap([5, 5, 5], fn
        x -> if x == 5, do: x
      end, & &1, 5)

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
end