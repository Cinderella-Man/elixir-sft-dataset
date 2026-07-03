Implement the private `handle_attempt_result/4` function. It is called from
`handle_info({:task_result, key, result}, state)` after a spawned Task reports the
outcome of an attempt, and it receives `key`, the current `entry` for that key,
the normalised `result`, and the full GenServer `state`. It must decide, based on
that result, whether to unblock the waiting callers or schedule another retry, and
return the appropriate GenServer callback tuple.

On success (`result` is `{:ok, _}`), reply to every caller in `entry.callers` with
the success value using `reply_all/2`, then clear the key from `state` and return
`{:noreply, updated_state}` so a subsequent `execute` triggers a fresh execution.

On failure (`result` is `{:error, _}`), check whether more retries remain, i.e.
`entry.attempt < entry.retry_config.max_retries`. If so, compute the next attempt
number (`entry.attempt + 1`), derive the backoff delay with `compute_delay/2`,
schedule a `{:retry_now, key}` message to `self()` after that delay using
`Process.send_after/3`, update the entry with the incremented `attempt` and a
`status` of `:waiting_retry`, store it back in `state`, and return `{:noreply, ...}`.
If the retry budget is exhausted, reply to all callers with the error via
`reply_all/2`, delete the key from `state`, and return `{:noreply, ...}`.

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

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{}, server_opts)
  end

  @spec execute(GenServer.server(), term(), (() -> term()), keyword()) ::
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

  @spec status(GenServer.server(), term()) :: :idle | {:retrying, pos_integer(), non_neg_integer()}
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
    # TODO
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