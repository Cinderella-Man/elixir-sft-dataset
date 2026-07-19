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
defmodule Dedup do
  @moduledoc """
  A GenServer that deduplicates concurrent identical requests.

  When `execute/3` is called with a key that has no in-flight execution,
  the given function is spawned in a separate task and the caller blocks
  until a result is available.

  If `execute/3` is called with a key that already has an in-flight
  execution, the new caller is queued and will receive the same result
  as all other waiters — without triggering a second execution of `func`.

  Once the task finishes (successfully or not), every waiting caller
  receives the result and the key is cleared, so the next call for that
  key starts a fresh execution.

  ## Result normalisation

  | `func` outcome              | What all callers receive          |
  |-----------------------------|-----------------------------------|
  | Returns `{:ok, value}`      | `{:ok, value}`                    |
  | Returns any other term `v`  | `{:ok, v}`                        |
  | Returns `{:error, reason}`  | `{:error, reason}`                |
  | Raises an exception `e`     | `{:error, {:exception, e}}`       |

  ## Example

      {:ok, _pid} = Dedup.start_link(name: MyDedup)

      # Both callers share a single execution of the slow function.
      Task.async(fn -> Dedup.execute(MyDedup, :my_key, fn -> expensive() end) end)
      Task.async(fn -> Dedup.execute(MyDedup, :my_key, fn -> expensive() end) end)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `Dedup` GenServer.

  Accepts all standard `GenServer.start_link/3` options, notably `:name`
  for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @doc """
  Executes `func` for the given `key`, deduplicating concurrent calls.

  Blocks the caller until the result is ready (no timeout is imposed;
  pass the call through a `Task` if you need a timeout on the caller's
  side).

  Returns `{:ok, value}` on success or `{:error, reason}` on failure.
  """
  @spec execute(GenServer.server(), term(), (-> term())) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func) when is_function(func, 0) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  # State shape:
  #   %{key => [GenServer.from()]}
  #
  # A key is present in the map if and only if a task is currently running
  # for it. The value is the (non-empty) list of callers waiting for the
  # result, in arrival order.

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:execute, key, func}, from, state) do
    case Map.fetch(state, key) do
      # -----------------------------------------------------------------------
      # No in-flight execution for this key — spawn one and register caller.
      # -----------------------------------------------------------------------
      :error ->
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

          send(parent, {:task_done, key, result})
        end)

        {:noreply, Map.put(state, key, [from])}

      # -----------------------------------------------------------------------
      # Execution already in flight — join the wait list, do not call func.
      # -----------------------------------------------------------------------
      {:ok, callers} ->
        {:noreply, Map.put(state, key, callers ++ [from])}
    end
  end

  @impl GenServer
  def handle_info({:task_done, key, result}, state) do
    # Pop the callers list and reply to every one of them with the same result.
    {callers, new_state} = Map.pop(state, key, [])
    Enum.each(callers, &GenServer.reply(&1, result))
    {:noreply, new_state}
  end

  # Ignore any other messages (e.g. stray task EXIT signals).
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
```

## New specification

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
