# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

# Bounded-Concurrency Concurrent Fetcher

Write me an Elixir module called `PooledFetcher` that fetches data from multiple sources concurrently but with a **bounded worker pool** — at most `max_concurrency` fetches may run at any instant, the rest wait in a queue — all under a single global timeout.

I need this function in the public API:

- `PooledFetcher.fetch_all(sources, max_concurrency, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, tuple, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `max_concurrency` is a positive integer — the maximum number of fetches allowed to run simultaneously.
  - `timeout_ms` is a single global wall-clock budget shared across the whole operation.

Behaviour:

- No more than `max_concurrency` fetches run at once. As each running fetch finishes, the next queued source is started, until all are done or the timeout fires.
- The timeout is a single global budget measured from the moment `fetch_all` is called — it is **not** reset per source and **not** reset when a queued source finally starts.
- The function returns a map of `%{name => result_tuple}` covering every source, where each value is one of:
  - `{:ok, value}` — the fetch completed successfully within the global timeout.
  - `{:error, reason}` — the fetch returned `{:error, reason}` or raised (crashes are captured).
  - `{:error, :timeout}` — the global timeout expired while this source was still **running or still waiting in the queue** (i.e. it never got a chance to finish).
- When the timeout fires, any still-running fetch processes must be killed immediately — no zombie processes left behind. The function returns only after all spawned processes are done or confirmed dead.
- If `sources` is empty, return `%{}` immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.). In particular, do not rely on `Task.async_stream/3`'s per-element timeout — the timeout here is global.

Give me the complete implementation in a single file with a single module.

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
