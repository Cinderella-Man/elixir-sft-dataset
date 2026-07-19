# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `loop` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `loop` missing

```elixir
defmodule PooledFetcher do
  @moduledoc """
  Fetches from multiple sources concurrently through a bounded worker pool under
  a single global timeout.

  At most `max_concurrency` fetches run at any instant; the rest wait in a
  queue and start as running slots free up. The timeout is a single wall-clock
  budget measured from the moment `fetch_all/3` is called — sources still
  running or still queued when it fires are reported as `{:error, :timeout}`,
  and any live process is killed before returning.

  Fetch processes are spawned *monitored but unlinked*, so a fetch that is
  killed from outside this module can never take the calling process down with
  it, whether or not the caller traps exits.
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
    loop(sources, %{}, %{}, max_concurrency, deadline)
  end

  defp loop(pending, running, results, max, deadline) do
    # TODO
  end

  # Waits for one worker message. The guards make sure only messages belonging
  # to this pool are consumed — unrelated mail in the caller's inbox is left
  # untouched.
  defp collect(pending, running, results, max, deadline, remaining) do
    receive do
      {:fetch_result, pid, reply} when is_map_key(running, pid) ->
        {ref, name} = Map.fetch!(running, pid)
        Process.demonitor(ref, [:flush])
        loop(pending, Map.delete(running, pid), Map.put(results, name, reply), max, deadline)

      {:DOWN, _ref, :process, pid, reason} when is_map_key(running, pid) ->
        {_ref, name} = Map.fetch!(running, pid)

        loop(
          pending,
          Map.delete(running, pid),
          Map.put(results, name, {:error, reason}),
          max,
          deadline
        )
    after
      remaining ->
        finalize_timeout(pending, running, results)
    end
  end

  # Starts queued fetches until the pool is full or the queue is empty.
  defp fill(pending, running, max) do
    if pending == [] or map_size(running) >= max do
      {pending, running}
    else
      [{name, fetch_fn} | rest] = pending
      parent = self()

      {pid, ref} =
        spawn_monitor(fn -> send(parent, {:fetch_result, self(), safe_call(fetch_fn)}) end)

      fill(rest, Map.put(running, pid, {ref, name}), max)
    end
  end

  # Kills every live fetch, waits for confirmation that it is gone, discards any
  # late result it may have sent, and marks running plus still-queued sources as
  # timed out.
  defp finalize_timeout(pending, running, results) do
    results =
      Enum.reduce(running, results, fn {pid, {ref, name}}, acc ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        end

        receive do
          {:fetch_result, ^pid, _reply} -> :ok
        after
          0 -> :ok
        end

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

Give me only the complete implementation of `loop` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
