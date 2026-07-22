# Fill in the middle: `PooledFetcher.finalize_timeout/4`

Below is a complete implementation of `PooledFetcher`, a module that fetches from
multiple sources concurrently through a bounded worker pool under a single global
timeout. Every function is intact **except** the private `finalize_timeout/4`, whose
body has been replaced with `# TODO`. Your job is to implement it.

## What `finalize_timeout/4` must do

`finalize_timeout/4` is the cleanup/shutdown path invoked from `loop/6` the moment
the global deadline is reached — either because the pre-`receive` check finds no
time remaining, or because the `receive ... after remaining` clause fires. Its
arguments are the current pool state at that instant:

- `pending` — the list of `{name, fetch_fn}` sources that were never started.
- `running` — a map of `monitor_ref => name` for fetches still in flight.
- `ref_to_task` — a map of `monitor_ref => %Task{}` for those same in-flight fetches.
- `results` — the map of `name => result_tuple` accumulated so far.

It must:

1. **Kill every live fetch immediately** so no zombie processes are left behind:
   for each `%Task{}` in `ref_to_task`, call `Task.shutdown(task, :brutal_kill)`.
2. **Mark every still-running source as timed out**: for each `{_ref, name}` in
   `running`, put `{:error, :timeout}` into `results` under that `name`.
3. **Mark every still-queued source as timed out**: for each `{name, _fetch_fn}` in
   `pending`, put `{:error, :timeout}` into `results` under that `name`.
4. **Return the final `results` map**, now covering every source (already-finished
   sources keep their real result; running and queued sources become
   `{:error, :timeout}`).

Sources that already completed before the timeout must keep their existing result
tuples untouched.

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
    # TODO
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