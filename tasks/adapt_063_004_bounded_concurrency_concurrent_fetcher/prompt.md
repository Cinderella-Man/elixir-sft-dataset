# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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
  @spec fetch_all([{term(), (-> {:ok, term()} | {:error, term()})}], non_neg_integer()) ::
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

# Bounded-Concurrency Concurrent Fetcher

Write me an Elixir module called `PooledFetcher` that fetches data from multiple sources concurrently but with a **bounded worker pool** — at most `max_concurrency` fetches may run at any instant, the rest wait in a queue — all under a single global timeout.

I need this function in the public API:

- `PooledFetcher.fetch_all(sources, max_concurrency, timeout_ms)` where:
  - `sources` is a list of `{name, fetch_fn}` tuples. `name` can be any term (atom, string, tuple, etc.) and `fetch_fn` is a zero-arity function that either returns `{:ok, result}` or returns `{:error, reason}` / raises.
  - `max_concurrency` is a positive integer — the maximum number of fetches allowed to run simultaneously.
  - `timeout_ms` is a single global wall-clock budget shared across the whole operation. It is a non-negative integer.

## Behaviour

### Pool and scheduling

- No more than `max_concurrency` fetches run at once — not even momentarily. As each running fetch finishes, the next queued source is started, until all are done or the timeout fires.
- Sources are started in the order they appear in `sources`: the first `max_concurrency` of them start immediately, and each subsequent one starts as soon as a slot frees up.
- If `max_concurrency` is greater than or equal to `length(sources)`, every source starts immediately and nothing is queued.
- Each fetch runs in its own process, so a fetch that blocks or sleeps only occupies its own slot and never blocks the caller from collecting other results.

### The global timeout

- The timeout is a single global budget measured from the moment `fetch_all` is called — it is **not** reset per source and **not** reset when a queued source finally starts. It is a wall-clock deadline: `now + timeout_ms`, tracked against a monotonic clock so it is immune to system-clock changes.
- Once the deadline has passed, `fetch_all` stops waiting for anything. Work that had already completed and been collected keeps its real result; everything else is reported as `{:error, :timeout}`.
- `timeout_ms: 0` means the budget is already spent: the deadline is checked before any result can be collected, so **every** source is reported as `{:error, :timeout}`, even ones whose `fetch_fn` would have returned instantly.
- When the timeout fires, any still-running fetch process must be killed immediately — no zombie processes left behind, and no late result may be delivered to the caller afterwards. `fetch_all` returns only after every process it spawned is finished or confirmed dead.

### Return value

The function returns a **map** of `%{name => result_tuple}` containing one entry for every distinct `name` in `sources`. Maps are unordered; callers get no ordering guarantee from the returned map. Each value is one of:

- `{:ok, value}` — `fetch_fn` returned `{:ok, value}` before the deadline. The `{:ok, value}` tuple is passed through unchanged.
- `{:error, reason}` — `fetch_fn` returned `{:error, reason}` before the deadline (passed through unchanged), or it failed in one of the ways below.
- `{:error, :timeout}` — the global timeout expired while this source was still **running or still waiting in the queue** (i.e. it never got a chance to finish).

### Failure normalisation

A fetch can never crash the caller. Whatever `fetch_fn` does, the corresponding entry is always a tagged two-tuple:

- Raises an exception → `{:error, exception}`, where `exception` is the exception struct itself (e.g. `%RuntimeError{message: "boom"}`), not a message string and not a re-raised error.
- Throws a value → `{:error, {:throw, thrown_value}}`.
- Exits → `{:error, {:exit, exit_reason}}`.
- Returns anything that is **not** an `{:ok, _}` or `{:error, _}` tuple (e.g. `:ok`, `42`, `nil`, a bare map) → `{:error, {:unexpected_return, the_returned_term}}`.
- Its process dies without delivering a result at all (e.g. it is killed by something outside this module) → `{:error, reason}` with that process's exit reason (for a `:kill`, that reason is `:killed`).

### Edge cases

- If `sources` is empty, return `%{}` immediately, regardless of `max_concurrency` and `timeout_ms` — nothing is spawned and no time is spent.
- `name` is used as a map key, so **names should be unique**. If a name appears more than once, the entries collapse into a single key whose value is whichever of them was recorded last, and the returned map therefore has fewer entries than `sources` has elements.
- Names are arbitrary terms and are never inspected, converted, or reordered — they come back as-is.
- `fetch_all` holds no shared or global state: calling it repeatedly (or concurrently from several processes) is safe, and each call gets a fresh pool, a fresh deadline, and an independent result map. A call leaves nothing behind that affects the next one.
- Calls with a `max_concurrency` that is not a positive integer, or a `timeout_ms` that is not a non-negative integer, are outside the supported contract — reject them with a guard clause on `fetch_all` so that such a call raises `FunctionClauseError`, rather than silently doing something surprising.

## Constraints

Do not use any external dependencies — only Elixir's standard library and OTP primitives (`Task`, `Process`, etc.). In particular, do not rely on `Task.async_stream/3`'s per-element timeout — the timeout here is global.

Give me the complete implementation in a single file with a single module.
