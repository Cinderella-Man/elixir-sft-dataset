# Fill-in-the-Middle: `PooledFetcher.fill/4`

The module below, `PooledFetcher`, fetches from multiple sources concurrently
through a bounded worker pool under a single global timeout. Every function is
already implemented **except** the private helper `fill/4`, whose body has been
replaced with `# TODO`. Implement `fill/4` so the module works as described.

## What `fill/4` must do

`fill/4` is the pool-filling helper called at the top of `loop/6`. Its job is to
start queued fetches until either the worker pool is full or the queue is empty,
returning the updated bookkeeping so `loop/6` can then wait for completions.

Signature and arguments:

- `fill(pending, running, ref_to_task, max)` where
  - `pending` — a list of `{name, fetch_fn}` tuples not yet started.
  - `running` — a map of `monitor_ref => name` for in-flight fetches.
  - `ref_to_task` — a map of `monitor_ref => %Task{}`, kept so tasks can be shut
    down on timeout.
  - `max` — the maximum number of fetches allowed to run simultaneously
    (`max_concurrency`).

Behaviour:

- It must return the 3-tuple `{pending, running, ref_to_task}` with any newly
  started fetches accounted for.
- **Base case:** if there is nothing left to start (`pending == []`) or the pool
  is already full (`map_size(running) >= max`), return
  `{pending, running, ref_to_task}` unchanged.
- **Recursive case:** otherwise, take the head `{name, fetch_fn}` off `pending`,
  start the fetch with `Task.async(fn -> safe_call(fetch_fn) end)`, then record
  it by putting `task.ref => name` into `running` and `task.ref => task` into
  `ref_to_task`. Recurse with the remaining `pending` (the tail) until the base
  case is reached.

Use `Task.async/1` (so each task is monitored and its `ref` is the reply/`:DOWN`
reference `loop/6` matches on) and delegate the actual invocation to the existing
`safe_call/1` helper. Do not change any other function.

## Module skeleton

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
    # TODO
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