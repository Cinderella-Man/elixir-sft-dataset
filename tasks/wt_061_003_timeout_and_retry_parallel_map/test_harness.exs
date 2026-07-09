defmodule RetryMapTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Basic correctness
  # -------------------------------------------------------

  test "empty collection returns []" do
    assert [] = RetryMap.pmap([], fn x -> x end, max_concurrency: 3)
  end

  test "all success returns tagged results in order" do
    results = RetryMap.pmap(1..5, fn x -> x * 10 end, max_concurrency: 2, timeout: 1000)
    assert results == [{:ok, 10}, {:ok, 20}, {:ok, 30}, {:ok, 40}, {:ok, 50}]
  end

  test "order preserved when tasks finish out of order" do
    results =
      RetryMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        max_concurrency: 6,
        timeout: 1000
      )

    assert results == Enum.map(1..6, &{:ok, &1})
  end

  # -------------------------------------------------------
  # Timeout + retry
  # -------------------------------------------------------

  test "an element that times out once but succeeds on retry returns {:ok, value}" do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    func = fn x ->
      n =
        Agent.get_and_update(agent, fn m ->
          c = Map.get(m, x, 0) + 1
          {c, Map.put(m, x, c)}
        end)

      if n == 1, do: Process.sleep(300)
      x * 2
    end

    results = RetryMap.pmap([1, 2, 3], func, max_concurrency: 3, timeout: 100, max_attempts: 3)
    assert results == [{:ok, 2}, {:ok, 4}, {:ok, 6}]
  end

  test "an element that always times out returns {:error, :timeout} after exhausting attempts" do
    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Process.sleep(500)
          :never
        end,
        max_concurrency: 1,
        timeout: 80,
        max_attempts: 2
      )

    assert results == [{:error, :timeout}]
  end

  # -------------------------------------------------------
  # Permanent failure (no retry)
  # -------------------------------------------------------

  test "an exception is permanent and is NOT retried" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Agent.update(agent, &(&1 + 1))
          raise "boom"
        end,
        max_concurrency: 1,
        timeout: 1000,
        max_attempts: 3
      )

    assert match?([{:error, {:exception, _}}], results)
    assert Agent.get(agent, & &1) == 1
  end

  test "a crash in one element does not affect the others" do
    results =
      RetryMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "only me"
          x -> x * 10
        end,
        max_concurrency: 3,
        timeout: 1000,
        max_attempts: 2
      )

    assert Enum.at(results, 0) == {:ok, 10}
    assert match?({:error, {:exception, _}}, Enum.at(results, 1))
    assert Enum.at(results, 2) == {:ok, 30}
  end

  # -------------------------------------------------------
  # Concurrency limit enforcement
  # -------------------------------------------------------

  test "never exceeds max_concurrency simultaneous tasks" do
    {:ok, counter} = ConcurrencyCounter.start_link([])

    RetryMap.pmap(
      1..8,
      fn _x ->
        ConcurrencyCounter.increment(counter)
        Process.sleep(60)
        ConcurrencyCounter.decrement(counter)
      end,
      max_concurrency: 3,
      timeout: 1000,
      max_attempts: 1
    )

    assert ConcurrencyCounter.peak(counter) <= 3
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
      ConcurrencyCounter.decrement(c)
      assert ConcurrencyCounter.peak(c) == 2
    end
  end
end
