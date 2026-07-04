# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PooledFetcher do
  @moduledoc """
  Fetches from multiple sources concurrently through a bounded worker pool under
  a single global timeout.

  At most `max_concurrency` fetches run at any instant; the rest wait in a
  queue and start as running slots free up. The timeout is a single wall-clock
  budget measured from the first call — sources still running or still queued
  when it fires are reported as `{:error, :timeout}`, and any live process is
  killed before returning.
  """

  @doc """
  Fetch from all sources with bounded concurrency, returning within `timeout_ms`.

  Returns `%{name => result_tuple}` where each value is `{:ok, value}`,
  `{:error, reason}`, or `{:error, :timeout}`.
  """
  @spec fetch_all(
          [{term(), (-> {:ok, term()} | {:error, term()})}],
          pos_integer(),
          non_neg_integer()
        ) :: %{term() => {:ok, term()} | {:error, term()}}
  def fetch_all([], _max_concurrency, _timeout_ms), do: %{}

  def fetch_all(sources, max_concurrency, timeout_ms)
      when is_list(sources) and is_integer(max_concurrency) and max_concurrency > 0 and
             is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    loop(sources, %{}, %{}, %{}, max_concurrency, deadline)
  end

  # Drives the pool: fill idle slots, then wait for the next completion or the
  # global deadline.
  #
  #   pending      - list of {name, fetch_fn} not yet started
  #   running      - map of monitor_ref => name for in-flight fetches
  #   ref_to_task  - map of monitor_ref => %Task{} for shutdown on timeout
  #   results      - map of name => result_tuple
  defp loop(pending, running, ref_to_task, results, max, deadline) do
    {pending, running, ref_to_task} = fill(pending, running, ref_to_task, max)

    if pending == [] and running == %{} do
      results
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        finalize_timeout(pending, running, ref_to_task, results)
      else
        receive do
          {ref, reply} when is_reference(ref) ->
            case Map.fetch(running, ref) do
              {:ok, name} ->
                Process.demonitor(ref, [:flush])

                loop(
                  pending,
                  Map.delete(running, ref),
                  Map.delete(ref_to_task, ref),
                  Map.put(results, name, reply),
                  max,
                  deadline
                )

              :error ->
                loop(pending, running, ref_to_task, results, max, deadline)
            end

          {:DOWN, ref, :process, _pid, reason} ->
            case Map.fetch(running, ref) do
              {:ok, name} ->
                loop(
                  pending,
                  Map.delete(running, ref),
                  Map.delete(ref_to_task, ref),
                  Map.put(results, name, {:error, reason}),
                  max,
                  deadline
                )

              :error ->
                loop(pending, running, ref_to_task, results, max, deadline)
            end
        after
          remaining ->
            finalize_timeout(pending, running, ref_to_task, results)
        end
      end
    end
  end

  # Starts queued fetches until the pool is full or the queue is empty.
  defp fill(pending, running, ref_to_task, max) do
    if pending == [] or map_size(running) >= max do
      {pending, running, ref_to_task}
    else
      [{name, fetch_fn} | rest] = pending
      task = Task.async(fn -> safe_call(fetch_fn) end)
      fill(rest, Map.put(running, task.ref, name), Map.put(ref_to_task, task.ref, task), max)
    end
  end

  # Kills every live fetch and marks both running and still-queued sources as
  # timed out.
  defp finalize_timeout(pending, running, ref_to_task, results) do
    Enum.each(ref_to_task, fn {_ref, task} -> Task.shutdown(task, :brutal_kill) end)

    results =
      Enum.reduce(running, results, fn {_ref, name}, acc ->
        Map.put(acc, name, {:error, :timeout})
      end)

    Enum.reduce(pending, results, fn {name, _fetch_fn}, acc ->
      Map.put(acc, name, {:error, :timeout})
    end)
  end

  # Normalises any exception, throw, exit, or unexpected return into a tagged
  # `{:ok, _} | {:error, _}` tuple so a fetch can never crash the caller.
  defp safe_call(fetch_fn) do
    case fetch_fn.() do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, value -> {:error, {kind, value}}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PooledFetcherTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp slow_ok(value, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:ok, value}
    end
  end

  defp slow_error(reason, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      {:error, reason}
    end
  end

  defp slow_raise(msg, delay_ms) do
    fn ->
      Process.sleep(delay_ms)
      raise RuntimeError, msg
    end
  end

  # -------------------------------------------------------
  # Basic behaviour
  # -------------------------------------------------------

  test "returns ok for all sources when the pool is large enough" do
    sources = [
      {:a, slow_ok(:ra, 10)},
      {:b, slow_ok(:rb, 10)},
      {:c, slow_ok(:rc, 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 5, 1_000)

    assert result == %{a: {:ok, :ra}, b: {:ok, :rb}, c: {:ok, :rc}}
  end

  test "handles error returns and crashes without affecting other fetches" do
    sources = [
      {:ok_src, slow_ok(:a, 10)},
      {:err, slow_error(:bad, 10)},
      {:boom, slow_raise("x", 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 1_000)

    assert result[:ok_src] == {:ok, :a}
    assert result[:err] == {:error, :bad}
    assert {:error, %RuntimeError{message: "x"}} = result[:boom]
  end

  # -------------------------------------------------------
  # Bounded concurrency
  # -------------------------------------------------------

  test "runs at most max_concurrency fetches at a time" do
    # 6 fetches of 100ms through a pool of 2 => ~3 sequential batches (~300ms).
    sources = for i <- 1..6, do: {i, slow_ok(i, 100)}

    start = System.monotonic_time(:millisecond)
    result = PooledFetcher.fetch_all(sources, 2, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..6, fn i -> result[i] == {:ok, i} end)
    assert elapsed >= 250, "pool appears unbounded (took only #{elapsed}ms)"
    assert elapsed < 800, "pool is slower than expected (took #{elapsed}ms)"
  end

  test "sources still queued or running when the timeout fires are reported as :timeout" do
    sources = [
      {:s1, slow_ok(:one, 100)},
      {:s2, slow_ok(:two, 100)},
      {:s3, slow_ok(:three, 100)},
      {:s4, slow_ok(:four, 100)}
    ]

    result = PooledFetcher.fetch_all(sources, 1, 150)

    assert result[:s1] == {:ok, :one}
    assert result[:s2] == {:error, :timeout}
    assert result[:s3] == {:error, :timeout}
    assert result[:s4] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert PooledFetcher.fetch_all([], 3, 1_000) == %{}
  end

  test "supports arbitrary term keys" do
    # TODO
  end

  test "single source" do
    assert PooledFetcher.fetch_all([{:only, slow_ok(:yes, 10)}], 2, 1_000) ==
             %{only: {:ok, :yes}}
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "timed-out and queued sources leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, slow_ok(i, 3_000)}
    PooledFetcher.fetch_all(sources, 3, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end
end
```
