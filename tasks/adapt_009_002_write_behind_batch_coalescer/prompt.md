# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

Write me an Elixir GenServer module called `BatchCollector` that collects individual items submitted under a key and flushes them as a batch to a user-supplied function, so that multiple rapid writes are coalesced into a single batch operation.

I need these functions in the public API:

- `BatchCollector.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a required `:flush_interval_ms` option (the maximum time to wait before flushing a batch, even if the count threshold hasn't been reached).

- `BatchCollector.submit(server, key, item, flush_fn, opts \\ [])` which adds `item` to the batch buffer for `key`. The caller blocks until its batch is flushed. `flush_fn` is a single-arity function that receives the list of all collected items for that key (in submission order) and returns `{:ok, result}` or `{:error, reason}`. The optional `:max_batch_size` in opts (default 10) controls the count threshold — when the buffer for a key reaches this size, it flushes immediately without waiting for the timer.

  Returns whatever `flush_fn` returns. All callers whose items are in the same batch receive the same result.

- `BatchCollector.pending_count(server, key)` which returns the number of items currently buffered for the given key (0 if no pending batch).

The lifecycle of a batch for a given key works like this:
1. The first `submit` for a key starts a timer of `flush_interval_ms` and puts the item in the buffer.
2. Subsequent `submit` calls for the same key add their items to the buffer and register as waiters.
3. When either the timer fires OR `max_batch_size` is reached (whichever comes first), the batch is flushed: `flush_fn` is called with the full list of items in a spawned Task (so the GenServer remains responsive), and all waiting callers receive the result.
4. After the flush, the key is cleared for new batches.

If `flush_fn` raises an exception, all callers in that batch should receive `{:error, {:exception, exception}}`.

If a timer fires but the batch was already flushed (because the count threshold was hit first), the timer message should be harmlessly ignored.

Different keys are completely independent — they have separate buffers, timers, and thresholds.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
