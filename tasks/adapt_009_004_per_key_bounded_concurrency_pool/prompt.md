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

Write me an Elixir GenServer module called `KeyedPool` that limits the number of concurrent executions per key, acting as a per-key bounded concurrency pool.

I need these functions in the public API:

- `KeyedPool.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a required `:max_concurrency` option (the maximum number of simultaneous executions allowed per key, must be a positive integer).

- `KeyedPool.execute(server, key, func)` where `func` is a zero-arity function. If the number of currently running executions for `key` is below `:max_concurrency`, the function is executed immediately in a spawned Task (so the GenServer remains responsive) and the caller blocks until the result is ready. If `:max_concurrency` executions are already running for that key, the caller is placed in a FIFO queue and blocks until a slot opens. When a running execution completes, the next queued caller's function is started.

  Each caller gets the result of **their own** function — this is NOT request deduplication. Every caller's function runs independently.

  Return value normalisation: if `func` returns `{:ok, value}`, the caller gets `{:ok, value}`. If `func` returns `{:error, reason}`, the caller gets `{:error, reason}`. If `func` returns any other term `v`, the caller gets `{:ok, v}`. If `func` raises, the caller gets `{:error, {:exception, exception}}`.

- `KeyedPool.status(server, key)` which returns a map `%{running: non_neg_integer(), queued: non_neg_integer()}` showing how many executions are running and how many callers are waiting in the queue for the given key. Returns `%{running: 0, queued: 0}` for keys with no activity.

When a slot frees up (a running execution finishes) and there are queued callers, the GenServer must automatically start the next queued caller's function. The queue is strictly FIFO.

Different keys are completely independent — each key has its own concurrency count and queue.

If a Task crashes (func raises), it must still free its slot and the queued caller's function should be started next. The crashing caller gets `{:error, {:exception, exception}}`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
