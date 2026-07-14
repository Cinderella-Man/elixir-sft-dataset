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

# Fallback-Chain Concurrent Fetcher

Write me an Elixir module called `FallbackFetcher` that fetches data from multiple sources concurrently, where **each source carries an ordered chain of fallback functions** that are tried in sequence until one succeeds, all under a single global timeout.

I need this function in the public API:

- `FallbackFetcher.fetch_all(sources, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fns}` tuples. `name` can be any term (atom, string, tuple, etc.).
  - `fetch_fns` is a list of zero-arity functions (the fallback chain). Each function either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `timeout_ms` is a single global wall-clock budget shared across every source.

Behaviour:

- Every source runs **concurrently** with every other source, starting the moment `fetch_all` is called.
- **Within a single source**, the fallback functions are tried **sequentially, in order**: try the first; if it returns `{:ok, value}`, that source is done with `{:ok, value}`; if it returns `{:error, reason}` or raises, move on to the next function; continue until one succeeds or the chain is exhausted.
- The function returns a map of `%{name => result_tuple}` where each value is one of:
  - `{:ok, value}` — some fallback in the chain succeeded within the timeout.
  - `{:error, {:all_failed, reasons}}` — every fallback failed; `reasons` is the list of failure reasons in the order the functions were tried (a raised exception is captured as its exception struct).
  - `{:error, :timeout}` — the global timeout expired while this source was still working through its chain.

Rules:

- The global timeout is shared across all sources, not per-source and not per-fallback. A source whose chain (summed sequentially) overruns the deadline is reported as `{:error, :timeout}`.
- When the timeout fires, any source still working must be killed immediately — no zombie processes. The function returns only after all spawned processes are done or confirmed dead.
- If `sources` is empty, return `%{}` immediately.

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.).

Give me the complete implementation in a single file with a single module.
