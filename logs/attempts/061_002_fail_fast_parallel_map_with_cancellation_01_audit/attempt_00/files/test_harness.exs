defmodule FailFastMapTest do
  use ExUnit.Case, async: false

  defp slow(value, ms) do
    Process.sleep(ms)
    value
  end

  # -------------------------------------------------------
  # Success path
  # -------------------------------------------------------

  test "empty collection returns {:ok, []}" do
    assert {:ok, []} = FailFastMap.pmap([], fn x -> x end, 3)
  end

  test "all-success returns {:ok, results} in original order" do
    input = Enum.to_list(1..20)
    assert {:ok, results} = FailFastMap.pmap(input, fn x -> x * 10 end, 4)
    assert results == Enum.map(input, &(&1 * 10))
  end

  test "order preserved even when tasks finish out of order" do
    assert {:ok, results} =
             FailFastMap.pmap(
               1..6,
               fn x ->
                 Process.sleep((7 - x) * 20)
                 x
               end,
               6
             )

    assert results == Enum.to_list(1..6)
  end

  test "works sequentially with max_concurrency of 1" do
    assert {:ok, [9, 1, 4]} = FailFastMap.pmap([3, 1, 2], fn x -> x * x end, 1)
  end

  # -------------------------------------------------------
  # Fail-fast path
  # -------------------------------------------------------

  test "first failure returns {:error, {index, reason}}" do
    assert {:error, {5, _reason}} =
             FailFastMap.pmap(
               1..6,
               fn
                 6 -> raise "boom"
                 x -> x * 2
               end,
               2
             )
  end

  test "failure at index 0 is reported with index 0" do
    assert {:error, {0, _reason}} =
             FailFastMap.pmap(
               [:bad, 2, 3],
               fn
                 :bad -> raise "nope"
                 x -> x
               end,
               3
             )
  end

  test "queued work is cancelled after a failure (not all elements started)" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    result =
      FailFastMap.pmap(
        1..30,
        fn
          1 ->
            raise "boom"

          _x ->
            ConcurrencyCounter.increment(counter)
            slow(:ok, 200)
            ConcurrencyCounter.decrement(counter)
        end,
        3
      )

    assert {:error, {0, _}} = result
    # Only the initial window (minus the failing element) could have started.
    assert ConcurrencyCounter.started(counter) < 30
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    assert {:ok, _} =
             FailFastMap.pmap(
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

  test "actually runs tasks in parallel" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    assert {:ok, _} =
             FailFastMap.pmap(
               1..6,
               fn _x ->
                 ConcurrencyCounter.increment(counter)
                 slow(:ok, 80)
                 ConcurrencyCounter.decrement(counter)
               end,
               3
             )

    assert ConcurrencyCounter.peak(counter) >= 2
  end

  # -------------------------------------------------------
  # ConcurrencyCounter unit tests
  # -------------------------------------------------------

  describe "ConcurrencyCounter" do
    test "tracks peak and started" do
      {:ok, c} = ConcurrencyCounter.start_link([])
      assert ConcurrencyCounter.increment(c) == 1
      assert ConcurrencyCounter.increment(c) == 2
      assert ConcurrencyCounter.decrement(c) == 1
      assert ConcurrencyCounter.peak(c) == 2
      assert ConcurrencyCounter.started(c) == 2
    end
  end

  test "still-running sibling tasks are killed when a failure short-circuits" do
    me = self()

    spawn_link(fn ->
      result =
        FailFastMap.pmap(
          [:bad, 2, 3],
          fn
            :bad ->
              slow(nil, 150)
              raise "boom"

            x ->
              send(me, {:started, x})
              slow(x, 2_000)
              send(me, {:finished, x})
          end,
          3
        )

      send(me, {:result, result})
    end)

    assert_receive {:started, 2}, 1_000
    assert_receive {:started, 3}, 1_000
    assert_receive {:result, {:error, {0, _reason}}}, 1_000
    refute_receive {:finished, _}, 800
  end

  test "a task that exits abnormally short-circuits with that element's index" do
    me = self()

    spawn_link(fn ->
      result =
        FailFastMap.pmap(
          [1, 2, 3],
          fn
            2 -> Process.exit(self(), :kill)
            x -> slow(x, 2_000)
          end,
          3
        )

      send(me, {:result, result})
    end)

    assert_receive {:result, {:error, {1, _reason}}}, 1_000
  end

  test "no element beyond the initial window is ever started after a failure" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    result =
      FailFastMap.pmap(
        1..30,
        fn
          1 ->
            slow(nil, 150)
            raise "boom"

          _x ->
            ConcurrencyCounter.increment(counter)
            slow(:ok, 1_000)
        end,
        3
      )

    assert {:error, {0, _reason}} = result
    # Window of 3 minus the failing element: exactly two elements may ever begin.
    assert ConcurrencyCounter.started(counter) == 2
  end

  test "ConcurrencyCounter start_link/1 registers the process under the given :name" do
    {:ok, pid} = ConcurrencyCounter.start_link(name: :audit_named_counter)

    assert Process.whereis(:audit_named_counter) == pid
    assert ConcurrencyCounter.increment(:audit_named_counter) == 1
    assert ConcurrencyCounter.decrement(:audit_named_counter) == 0
    assert ConcurrencyCounter.peak(:audit_named_counter) == 1
    assert ConcurrencyCounter.started(:audit_named_counter) == 1
  end
end
