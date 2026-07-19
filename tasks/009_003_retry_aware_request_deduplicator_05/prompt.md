# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `RetryDedup` that deduplicates concurrent identical requests (like a standard coalescer) but automatically retries failed executions with exponential backoff before returning to callers.

I need these functions in the public API:

- `RetryDedup.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `RetryDedup.execute(server, key, func, opts \\ [])` where `func` is a zero-arity function. Like a standard deduplicator: if no execution is currently in flight for the given `key`, the function is executed asynchronously and the caller blocks. If another caller calls `execute` with the same key while execution (or retries) are still in progress, it joins the wait list without triggering another execution.

  Options:
    - `:max_retries` — maximum number of retry attempts after the initial failure (default 3)
    - `:base_delay_ms` — initial retry delay in milliseconds (default 100)
    - `:max_delay_ms` — cap on the retry delay (default 5000)

  Retry behaviour: if `func` raises or returns `{:error, reason}`, the GenServer schedules a retry after an exponentially increasing delay: `min(base_delay_ms * 2^attempt, max_delay_ms)`. On retry, `func` is called again in a new spawned Task. If `func` eventually succeeds within the retry budget, all waiting callers receive the success result. If all retries are exhausted, all waiting callers receive the last error.

  The caller blocks until the final result is available — no matter how long the whole retry sequence takes — so `execute` must not impose its own call timeout (the retry sequence can easily exceed the default 5-second `GenServer.call` timeout).
  The GenServer itself must NEVER block during retry delays: retries are
  scheduled asynchronously (the server stays responsive), so an `execute` for a
  DIFFERENT key completes immediately even while another key's retry sequence
  is mid-backoff.

  Callers that arrive during retries (between attempts) also join the wait list and get the eventual result — they do NOT restart the retry sequence.

  Return value normalisation: if `func` returns `{:ok, value}`, callers get `{:ok, value}`. If `func` returns `{:error, reason}`, callers get `{:error, reason}`. If `func` returns any other term `v`, callers get `{:ok, v}`. If `func` raises, it's treated as `{:error, {:exception, exception}}` for retry purposes — so if all retries are exhausted after a raise, callers get `{:error, {:exception, exception}}` where `exception` is the raised exception struct.

- `RetryDedup.status(server, key)` which returns `:idle` if no execution is in progress for the key, or `{:retrying, attempt, max_retries}` if retries are in progress (attempt is 1-based, counting from the first retry).

After either final success or final failure, the key is cleared so subsequent calls trigger a fresh execution.

The GenServer must not execute `func` inside `handle_call` — always spawn a Task so the GenServer remains responsive.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- `status/2` also returns `:idle` during the initial attempt: while `func` is
  running for the first time and no retry has been scheduled yet, the key's
  status is `:idle` — indistinguishable from an unknown key.
  `{:retrying, attempt, max_retries}` appears only once at least one retry has
  been scheduled.

## The module with `start_link` missing

```elixir
defmodule RetryDedup do
  @moduledoc """
  A GenServer that deduplicates concurrent requests per key and automatically
  retries failed executions with exponential backoff.

  Callers that arrive while an execution (or its retry sequence) is in flight
  join the wait list and receive the eventual result — whether success after
  retries, or the final error when the retry budget is exhausted.

  ## Retry semantics

  On failure (raise or `{:error, _}`), the GenServer waits
  `min(base_delay_ms * 2^attempt, max_delay_ms)` then re-invokes `func` in a
  fresh Task. Callers are only unblocked once either:
    - `func` succeeds, or
    - all retries are exhausted.

  ## Example

      {:ok, pid} = RetryDedup.start_link([])
      counter = :counters.new(1, [:atomics])

      result = RetryDedup.execute(pid, :flaky, fn ->
        n = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        if n < 2, do: {:error, :not_yet}, else: {:ok, :finally}
      end, max_retries: 5)

      result  #=> {:ok, :finally}
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    # TODO
  end

  @doc """
  Runs `func` under `key`, coalescing concurrent duplicate calls into one execution
  and retrying per `opts`. Returns the function's result.
  """
  @spec execute(GenServer.server(), term(), (-> term()), keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func, opts \\ []) when is_function(func, 0) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 100)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 5_000)

    retry_config = %{
      max_retries: max_retries,
      base_delay_ms: base_delay_ms,
      max_delay_ms: max_delay_ms
    }

    GenServer.call(server, {:execute, key, func, retry_config}, :infinity)
  end

  @spec status(GenServer.server(), term()) ::
          :idle | {:retrying, pos_integer(), non_neg_integer()}
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  # State shape:
  #   %{
  #     key => %{
  #       callers:      [GenServer.from()],
  #       func:         (() -> term()),
  #       retry_config: %{max_retries: _, base_delay_ms: _, max_delay_ms: _},
  #       attempt:      non_neg_integer(),  # 0 = initial, 1 = first retry, ...
  #       status:       :running | :waiting_retry
  #     }
  #   }

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:execute, key, func, retry_config}, from, state) do
    case Map.fetch(state, key) do
      :error ->
        spawn_attempt(key, func)

        entry = %{
          callers: [from],
          func: func,
          retry_config: retry_config,
          attempt: 0,
          status: :running
        }

        {:noreply, Map.put(state, key, entry)}

      {:ok, entry} ->
        updated = %{entry | callers: entry.callers ++ [from]}
        {:noreply, Map.put(state, key, updated)}
    end
  end

  def handle_call({:status, key}, _from, state) do
    reply =
      case Map.fetch(state, key) do
        {:ok, %{attempt: attempt, retry_config: %{max_retries: max}}} when attempt > 0 ->
          {:retrying, attempt, max}

        {:ok, _} ->
          :idle

        :error ->
          :idle
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:task_result, key, result}, state) do
    case Map.fetch(state, key) do
      {:ok, entry} ->
        handle_attempt_result(key, entry, result, state)

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:retry_now, key}, state) do
    case Map.fetch(state, key) do
      {:ok, %{func: func} = entry} ->
        spawn_attempt(key, func)
        {:noreply, Map.put(state, key, %{entry | status: :running})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp handle_attempt_result(key, entry, result, state) do
    case result do
      {:ok, _} = success ->
        reply_all(entry.callers, success)
        {:noreply, Map.delete(state, key)}

      {:error, _} = error ->
        if entry.attempt < entry.retry_config.max_retries do
          next_attempt = entry.attempt + 1
          delay = compute_delay(next_attempt, entry.retry_config)
          Process.send_after(self(), {:retry_now, key}, delay)

          updated = %{entry | attempt: next_attempt, status: :waiting_retry}
          {:noreply, Map.put(state, key, updated)}
        else
          reply_all(entry.callers, error)
          {:noreply, Map.delete(state, key)}
        end
    end
  end

  defp spawn_attempt(key, func) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          case func.() do
            {:ok, _} = ok -> ok
            {:error, _} = err -> err
            other -> {:ok, other}
          end
        rescue
          exception -> {:error, {:exception, exception}}
        end

      send(parent, {:task_result, key, result})
    end)
  end

  defp compute_delay(attempt, %{base_delay_ms: base, max_delay_ms: max_d}) do
    # attempt is 1-based here (first retry = attempt 1)
    raw = base * Integer.pow(2, attempt - 1)
    min(raw, max_d)
  end

  defp reply_all(callers, result) do
    Enum.each(callers, &GenServer.reply(&1, result))
  end
end
```

Give me only the complete implementation of `start_link` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
