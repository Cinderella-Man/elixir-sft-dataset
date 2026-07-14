# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule ConcurrentFetcher do
  @moduledoc """
  Fetches data from multiple sources concurrently under a single global timeout.

  All fetches begin at the same instant. The timeout budget is shared — it is
  not reset or re-applied per source. Any source that has not completed by the
  time the deadline fires is killed immediately and reported as
  `{:error, :timeout}`.
  """

  @doc """
  Fetch from all sources concurrently, returning results within `timeout_ms`.

  ## Parameters
  - `sources`    – list of `{name, fetch_fn}` tuples.
                   `name` is any term; `fetch_fn` is a zero-arity function
                   returning `{:ok, value}` or `{:error, reason}` (raising is
                   also handled gracefully).
  - `timeout_ms` – global wall-clock budget in milliseconds, shared by every
                   concurrent fetch.

  ## Return value
  A map of `%{name => result_tuple}` where each value is one of:

  - `{:ok, value}`          – fetch completed successfully within the timeout
  - `{:error, :timeout}`    – global timeout expired before this fetch finished
  - `{:error, reason}`      – fetch function raised or returned `{:error, reason}`

  Returns `%{}` immediately when `sources` is empty.
  """
  @spec fetch_all([{term(), (-> {:ok, term()} | {:error, term()})}, ...], non_neg_integer()) ::
          %{term() => {:ok, term()} | {:error, term()}}
  def fetch_all([], _timeout_ms), do: %{}

  def fetch_all(sources, timeout_ms)
      when is_list(sources) and is_integer(timeout_ms) and timeout_ms >= 0 do
    # ── 1. Spawn every fetch concurrently ──────────────────────────────────
    # Task.async/1 links the task to the caller, which lets us kill it later
    # via Task.shutdown/2. We pair each Task struct with its source name so we
    # can reconstruct the result map afterwards.
    tagged_tasks =
      Enum.map(sources, fn {name, fetch_fn} ->
        task = Task.async(fn -> safe_call(fetch_fn) end)
        {name, task}
      end)

    tasks = Enum.map(tagged_tasks, fn {_name, task} -> task end)

    # ── 2. Wait for all tasks under the global timeout ─────────────────────
    # Task.yield_many/2 blocks for at most `timeout_ms` milliseconds and then
    # returns a list of {task, result_or_nil} pairs in the same order as the
    # input list.  A nil result means the task did not finish in time.
    yield_results = Task.yield_many(tasks, timeout_ms)

    # ── 3. Reconcile each task's outcome ──────────────────────────────────
    # Build a map from task reference → final result_tuple first, then
    # re-attach names.
    ref_to_result =
      Enum.reduce(yield_results, %{}, fn {task, yield_outcome}, acc ->
        result =
          case yield_outcome do
            # Task completed within the timeout window.
            {:ok, {:ok, value}} ->
              {:ok, value}

            # Task completed but returned an application-level error.
            {:ok, {:error, reason}} ->
              {:error, reason}

            # Task exited/raised before the timeout fired.
            {:exit, reason} ->
              {:error, reason}

            # Timeout: the task is still running — shut it down immediately.
            # Task.shutdown/2 sends an exit signal and waits for the process
            # to terminate, so no zombie processes are left behind.
            nil ->
              Task.shutdown(task, :brutal_kill)
              {:error, :timeout}
          end

        Map.put(acc, task.ref, result)
      end)

    # ── 4. Rebuild the caller-facing map keyed by source name ─────────────
    Map.new(tagged_tasks, fn {name, task} ->
      {name, Map.fetch!(ref_to_result, task.ref)}
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Wraps the user-supplied fetch function so that any exception or unexpected
  # return value is normalised into {:ok, _} | {:error, _} without leaking raw
  # EXIT signals to the caller.
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

## New specification

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
