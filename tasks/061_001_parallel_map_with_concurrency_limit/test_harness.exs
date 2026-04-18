defmodule ParallelMapTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Sleeps for `ms` then returns the value — used to keep tasks alive long
  # enough for the concurrency counter to observe them.
  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "maps over an empty collection" do
    assert [] = ParallelMap.pmap([], fn x -> x * 2 end, 3)
  end

  test "returns results in original order" do
    input = Enum.to_list(1..20)

    results = ParallelMap.pmap(input, fn x -> x * 10 end, 4)

    assert results == Enum.map(input, &(&1 * 10))
  end

  test "works when collection is smaller than max_concurrency" do
    results = ParallelMap.pmap([1, 2], fn x -> x + 1 end, 10)
    assert results == [2, 3]
  end

  test "works with max_concurrency of 1 (sequential)" do
    results = ParallelMap.pmap([3, 1, 2], fn x -> x * x end, 1)
    assert results == [9, 1, 4]
  end

  test "works with max_concurrency equal to collection size" do
    results = ParallelMap.pmap([1, 2, 3], fn x -> x + 100 end, 3)
    assert results == [101, 102, 103]
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency=3 simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..10,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 60)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    assert ConcurrencyCounter.peak(counter) <= 3
  end

  test "actually runs tasks in parallel (peak > 1 with concurrency > 1)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..6,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 80)
        ConcurrencyCounter.decrement(counter)
      end,
      3
    )

    # With 6 items and max 3, we should reach at least 2 simultaneously
    assert ConcurrencyCounter.peak(counter) >= 2
  end

  test "max_concurrency=1 never exceeds 1 simultaneous task" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    ParallelMap.pmap(
      1..5,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        slow(:ok, 30)
        ConcurrencyCounter.decrement(counter)
      end,
      1
    )

    assert ConcurrencyCounter.peak(counter) == 1
  end

  # -------------------------------------------------------
  # Crash / error handling
  # -------------------------------------------------------

  test "a crashing function returns {:error, reason} for that item" do
    results =
      ParallelMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "boom"
          x -> x * 10
        end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end

  test "crash in one task does not cancel other tasks" do
    results =
      ParallelMap.pmap(
        1..5,
        fn
          3 -> raise "only me"
          x -> slow(x * 2, 40)
        end,
        5
      )

    assert Enum.at(results, 0) == 2
    assert Enum.at(results, 1) == 4
    assert match?({:error, _}, Enum.at(results, 2))
    assert Enum.at(results, 3) == 8
    assert Enum.at(results, 4) == 10
  end

  test "all items crash — returns all error tuples" do
    results = ParallelMap.pmap([1, 2, 3], fn _ -> raise "always" end, 2)

    assert length(results) == 3
    assert Enum.all?(results, &match?({:error, _}, &1))
  end

  test "result order is preserved even when tasks finish out of order" do
    # Items with larger index sleep longer, so they finish last
    input = Enum.to_list(1..6)

    results =
      ParallelMap.pmap(
        input,
        fn x ->
          # item 1 sleeps longest
          Process.sleep((7 - x) * 20)
          x
        end,
        6
      )

    assert results == input
  end

  # -------------------------------------------------------
  # ConcurrencyCounter unit tests
  # -------------------------------------------------------

  describe "ConcurrencyCounter" do
    test "starts at zero and tracks peak" do
      {:ok, c} = ConcurrencyCounter.start_link([])

      assert ConcurrencyCounter.peak(c) == 0

      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.decrement(c)

      assert ConcurrencyCounter.peak(c) == 3
    end

    test "increment returns the new count" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.increment(c) == 1
      assert ConcurrencyCounter.increment(c) == 2
    end

    test "decrement returns the new count" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      ConcurrencyCounter.increment(c)
      ConcurrencyCounter.increment(c)
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.decrement(c) == 0
    end
  end
end
