# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

# Quorum First-N Concurrent Fetcher

Write me an Elixir module called `QuorumFetcher` that races data fetches from multiple sources concurrently and returns **as soon as a quorum of successes is reached**, cancelling everything still in flight.

I need this function in the public API:

- `QuorumFetcher.fetch_first(sources, count, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, tuple, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `count` is the number of **successful** fetches required (the quorum).
  - `timeout_ms` is a single global wall-clock budget shared across every fetch.

All fetches begin concurrently the moment `fetch_first` is called. The function returns a map of `%{name => result_tuple}` covering **every** source, where each value is one of:

- `{:ok, value}` — this fetch completed successfully (winners plus any source that had already succeeded).
- `{:error, reason}` — this fetch returned `{:error, reason}` or raised (crashes are captured, never counted as a success).
- `{:error, :cancelled}` — the quorum was reached and this source was still running, so it was cancelled.
- `{:error, :timeout}` — the global timeout expired before the quorum could be reached and this source had not finished.

Semantics:

- The function returns the instant the `count`-th success arrives; it must not wait for slower sources.
- When the quorum is reached, any still-running fetch processes must be killed immediately — no zombies. Still-running sources are reported as `{:error, :cancelled}`.
- If the quorum can never be met before the timeout, sources that finished are reported with their real outcome (`{:ok, …}` or `{:error, reason}`) and unfinished sources become `{:error, :timeout}`.
- If `sources` is empty, return `%{}` immediately.
- If `count <= 0`, the quorum is trivially satisfied: nothing is run and every source is reported as `{:error, :cancelled}`.
- The function returns only after every spawned process is done or confirmed dead.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.

## The buggy module

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
    Map.new(sources, fn {name, _fetch_fn} -> {name, {:ok, :cancelled}} end)
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

## Failing test report

```
2 of 14 test(s) failed:

  * test a non-positive quorum cancels every source without running it
      
      
      Assertion with == failed
      code:  assert result == %{a: {:error, :cancelled}, b: {:error, :cancelled}}
      left:  %{a: {:ok, :cancelled}, b: {:ok, :cancelled}}
      right: %{a: {:error, :cancelled}, b: {:error, :cancelled}}
      

  * test a non-positive quorum never invokes any fetch function
      
      
      Assertion with == failed
      code:  assert QuorumFetcher.fetch_first(sources, -1, 1000) == %{
                    a: {:error, :cancelled},
                    b: {:error, :cancelled}
                  }
      left:  %{a: {:ok, :cancelled}, b: {:ok, :cancelled}}
      right: %{a: {:error, :cancelled}, b: {:error, :cancelled}}
```
