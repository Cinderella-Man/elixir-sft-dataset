# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule QuorumFetcher do
  @moduledoc """
  Races concurrent fetches under a single global timeout and returns as soon as
  a quorum of successful results is reached.

  All fetches start at the same instant. The moment the `count`-th success
  arrives, any source still running is killed and reported as
  `{:error, :cancelled}`. If the quorum cannot be met before the shared deadline
  fires, unfinished sources are reported as `{:error, :timeout}`.
  """

  @doc """
  Fetch concurrently, returning once `count` sources have succeeded.

  Returns a map of `%{name => result_tuple}` covering every source, where each
  value is `{:ok, value}`, `{:error, reason}`, `{:error, :cancelled}`, or
  `{:error, :timeout}`.
  """
  @spec fetch_first(
          [{term(), (-> {:ok, term()} | {:error, term()})}],
          integer(),
          non_neg_integer()
        ) :: %{term() => {:ok, term()} | {:error, term()}}
  def fetch_first([], _count, _timeout_ms), do: %{}

  def fetch_first(sources, count, _timeout_ms)
      when is_list(sources) and is_integer(count) and count <= 0 do
    Map.new(sources, fn {name, _fetch_fn} -> {name, {:error, :cancelled}} end)
  end

  def fetch_first(sources, count, timeout_ms)
      when is_list(sources) and is_integer(count) and is_integer(timeout_ms) and
             timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    tagged =
      Enum.map(sources, fn {name, fetch_fn} ->
        task = Task.async(fn -> safe_call(fetch_fn) end)
        {task.ref, name, task}
      end)

    ref_to_name = Map.new(tagged, fn {ref, name, _task} -> {ref, name} end)
    ref_to_task = Map.new(tagged, fn {ref, _name, task} -> {ref, task} end)
    all_refs = MapSet.new(Map.keys(ref_to_name))

    {results, reached?} = collect(%{}, 0, count, all_refs, deadline)

    fill_result = if reached?, do: {:error, :cancelled}, else: {:error, :timeout}

    final =
      Enum.reduce(all_refs, results, fn ref, acc ->
        if Map.has_key?(acc, ref) do
          acc
        else
          # A task that completed just before the kill has its reply in
          # Task.shutdown's return — that source "had already succeeded"
          # (or failed) and must be reported with its REAL outcome, not
          # blanket-cancelled.
          case Task.shutdown(Map.fetch!(ref_to_task, ref), :brutal_kill) do
            {:ok, real_outcome} -> Map.put(acc, ref, real_outcome)
            _ -> Map.put(acc, ref, fill_result)
          end
        end
      end)

    Map.new(final, fn {ref, result} -> {Map.fetch!(ref_to_name, ref), result} end)
  end

  # Blocks until the quorum is met, every task has reported, or the deadline
  # elapses. Returns `{results_by_ref, reached_quorum?}`.
  defp collect(results, success_count, quorum, all_refs, deadline) do
    cond do
      success_count >= quorum ->
        {results, true}

      map_size(results) == MapSet.size(all_refs) ->
        {results, false}

      true ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {results, false}
        else
          receive do
            {ref, reply} when is_reference(ref) ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                Process.demonitor(ref, [:flush])

                new_success =
                  case reply do
                    {:ok, _} -> success_count + 1
                    _ -> success_count
                  end

                collect(Map.put(results, ref, reply), new_success, quorum, all_refs, deadline)
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end

            {:DOWN, ref, :process, _pid, reason} ->
              if MapSet.member?(all_refs, ref) and not Map.has_key?(results, ref) do
                collect(
                  Map.put(results, ref, {:error, reason}),
                  success_count,
                  quorum,
                  all_refs,
                  deadline
                )
              else
                collect(results, success_count, quorum, all_refs, deadline)
              end
          after
            remaining ->
              {results, false}
          end
        end
    end
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
defmodule QuorumFetcherTest do
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
  # Quorum behaviour
  # -------------------------------------------------------

  test "returns as soon as the quorum of successes is reached and cancels the rest" do
    sources = [
      {:a, slow_ok(:ra, 20)},
      {:b, slow_ok(:rb, 20)},
      {:c, slow_ok(:rc, 20)},
      {:d, slow_ok(:rd, 3_000)},
      {:e, slow_ok(:re, 3_000)}
    ]

    start = System.monotonic_time(:millisecond)
    result = QuorumFetcher.fetch_first(sources, 3, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert result[:a] == {:ok, :ra}
    assert result[:b] == {:ok, :rb}
    assert result[:c] == {:ok, :rc}
    assert result[:d] == {:error, :cancelled}
    assert result[:e] == {:error, :cancelled}
    assert elapsed < 500, "should not wait for the slow sources (took #{elapsed}ms)"
  end

  test "sources that finish with an error do not count toward the quorum" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert result[:err] == {:error, :nope}
    assert result[:win] == {:ok, :yes}
  end

  test "a crashing source is reported as an error, not a success" do
    sources = [
      {:boom, slow_raise("kaboom", 10)},
      {:win, slow_ok(:yes, 120)}
    ]

    result = QuorumFetcher.fetch_first(sources, 1, 1_000)

    assert {:error, reason} = result[:boom]
    assert reason != :cancelled
    assert reason != :timeout
    assert result[:win] == {:ok, :yes}
  end

  # -------------------------------------------------------
  # Timeout behaviour
  # -------------------------------------------------------

  test "still-running sources become :timeout when the quorum can't be met in time" do
    sources = [
      {:a, slow_ok(:a, 10)},
      {:b, slow_ok(:b, 10)},
      {:c, slow_ok(:c, 3_000)},
      {:d, slow_ok(:d, 3_000)},
      {:e, slow_ok(:e, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 5, 150)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:ok, :b}
    assert result[:c] == {:error, :timeout}
    assert result[:d] == {:error, :timeout}
    assert result[:e] == {:error, :timeout}
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty sources returns an empty map" do
    assert QuorumFetcher.fetch_first([], 3, 1_000) == %{}
  end

  test "a non-positive quorum cancels every source without running it" do
    # TODO
  end

  test "supports arbitrary term keys" do
    sources = [
      {"s", slow_ok(1, 10)},
      {42, slow_ok(2, 10)},
      {{:t}, slow_ok(3, 10)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 1_000)

    assert result["s"] == {:ok, 1}
    assert result[42] == {:ok, 2}
    assert result[{:t}] == {:ok, 3}
  end

  # -------------------------------------------------------
  # No zombie processes
  # -------------------------------------------------------

  test "cancelled and timed-out sources leave no zombie processes behind" do
    before_pids = MapSet.new(Process.list())

    sources = for i <- 1..10, do: {i, slow_ok(i, 3_000)}

    QuorumFetcher.fetch_first(sources, 2, 100)
    Process.sleep(50)

    new_pids = MapSet.difference(MapSet.new(Process.list()), before_pids)

    assert MapSet.size(new_pids) == 0,
           "expected no leftover processes, found #{inspect(MapSet.to_list(new_pids))}"
  end

  test "a non-positive quorum never invokes any fetch function" do
    parent = self()

    probe = fn name ->
      fn ->
        send(parent, {:invoked, name})
        {:ok, name}
      end
    end

    sources = [{:a, probe.(:a)}, {:b, probe.(:b)}]

    assert QuorumFetcher.fetch_first(sources, -1, 1_000) ==
             %{a: {:error, :cancelled}, b: {:error, :cancelled}}

    refute_receive {:invoked, _}, 100
  end

  test "every source has started before any of them is allowed to complete" do
    parent = self()

    gated = fn name ->
      fn ->
        send(parent, {:started, name, self()})

        receive do
          :go -> {:ok, name}
        end
      end
    end

    sources = [{:a, gated.(:a)}, {:b, gated.(:b)}, {:c, gated.(:c)}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, _}, 1_000
    assert_receive {:started, :c, _}, 1_000

    send(pid_a, :go)

    result = Task.await(caller, 5_000)

    assert result[:a] == {:ok, :a}
    assert result[:b] == {:error, :cancelled}
    assert result[:c] == {:error, :cancelled}
  end

  test "a cancelled source's fetch function is interrupted before it can finish its work" do
    parent = self()

    winner = fn ->
      send(parent, {:started, :w, self()})

      receive do
        :go -> {:ok, :w}
      end
    end

    loser = fn ->
      send(parent, {:started, :slow, self()})

      receive do
        :never -> :ok
      after
        1_000 -> send(parent, {:completed, :slow})
      end

      {:ok, :slow}
    end

    sources = [{:w, winner}, {:slow, loser}]

    caller =
      Task.async(fn -> QuorumFetcher.fetch_first(sources, 1, 5_000) end)

    assert_receive {:started, :w, pid_w}, 1_000
    assert_receive {:started, :slow, _}, 1_000

    send(pid_w, :go)

    result = Task.await(caller, 5_000)

    assert result[:w] == {:ok, :w}
    assert result[:slow] == {:error, :cancelled}
    refute_receive {:completed, :slow}, 1_500
  end

  test "no spawned process is still alive the moment fetch_first returns" do
    parent = self()

    hang = fn name ->
      fn ->
        send(parent, {:pid, name, self()})

        receive do
          :never -> {:ok, name}
        end
      end
    end

    sources = [{:a, hang.(:a)}, {:b, hang.(:b)}, {:c, hang.(:c)}]

    result = QuorumFetcher.fetch_first(sources, 3, 100)

    assert_receive {:pid, :a, pid_a}, 1_000
    assert_receive {:pid, :b, pid_b}, 1_000
    assert_receive {:pid, :c, pid_c}, 1_000

    for pid <- [pid_a, pid_b, pid_c] do
      refute Process.alive?(pid),
             "spawned process #{inspect(pid)} outlived fetch_first"
    end

    assert result[:a] == {:error, :timeout}
    assert result[:b] == {:error, :timeout}
    assert result[:c] == {:error, :timeout}
  end

  test "on timeout, finished failing and crashing sources keep their real outcome" do
    sources = [
      {:err, slow_error(:nope, 10)},
      {:boom, slow_raise("kaboom", 10)},
      {:slow, slow_ok(:s, 3_000)}
    ]

    result = QuorumFetcher.fetch_first(sources, 3, 200)

    assert result[:err] == {:error, :nope}
    assert {:error, reason} = result[:boom]
    assert reason != :timeout
    assert reason != :cancelled
    assert result[:slow] == {:error, :timeout}
  end

  test "sources that finished before the kill report their real outcome" do
    # Fifty instant sources with a quorum of one: dozens complete before the
    # post-quorum shutdown sweep, and each such reply is sitting in the
    # mailbox — those sources "had already succeeded" and may not be
    # blanket-cancelled.
    sources = for i <- 1..50, do: {:"s#{i}", fn -> {:ok, i} end}

    results = QuorumFetcher.fetch_first(sources, 1, 5_000)

    ok_count = Enum.count(results, fn {_name, r} -> match?({:ok, _}, r) end)
    assert ok_count >= 2
  end
end
```
