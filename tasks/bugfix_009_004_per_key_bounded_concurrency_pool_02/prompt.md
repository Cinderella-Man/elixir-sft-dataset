# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

```elixir
defmodule KeyedPool do
  @moduledoc """
  A GenServer that limits concurrent executions per key, acting as a
  per-key bounded concurrency pool.

  Unlike a request deduplicator, every caller's function runs independently —
  the pool simply gates *how many* can run simultaneously for a given key.
  Excess callers are queued FIFO and started automatically as slots free up.

  ## Example

      {:ok, pid} = KeyedPool.start_link(max_concurrency: 2)

      # Up to 2 tasks for :db can run at once; the 3rd waits in the queue.
      tasks = for i <- 1..3 do
        Task.async(fn ->
          KeyedPool.execute(pid, :db, fn ->
            Process.sleep(100)
            {:ok, i}
          end)
        end)
      end

      Task.await_many(tasks)
      #=> [{:ok, 1}, {:ok, 2}, {:ok, 3}]
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    max_concurrency = Keyword.fetch!(opts, :max_concurrency)

    if not is_integer(max_concurrency) or max_concurrency < 1 do
      raise ArgumentError,
            ":max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
    end

    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{max_concurrency: max_concurrency}, server_opts)
  end

  @doc """
  Runs `func` under `key` with per-key bounded concurrency, queueing when the key is
  at capacity. Returns the function's result.
  """
  @spec execute(GenServer.server(), term(), (-> term())) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func) when is_function(func, 1) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end

  @spec status(GenServer.server(), term()) :: %{
          running: non_neg_integer(),
          queued: non_neg_integer()
        }
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  # State shape:
  #   %{
  #     max_concurrency: pos_integer(),
  #     keys: %{
  #       key => %{
  #         running:  non_neg_integer(),       # count of in-flight tasks
  #         queue:    [{from, func}],           # FIFO queue of waiting callers
  #         tasks:    %{reference() => from}    # task ref => caller who owns it
  #       }
  #     }
  #   }

  @impl GenServer
  def init(config) do
    {:ok, Map.put(config, :keys, %{})}
  end

  @impl GenServer
  def handle_call({:execute, key, func}, from, state) do
    key_state = Map.get(state.keys, key, empty_key_state())

    if key_state.running < state.max_concurrency do
      # Slot available — start immediately
      new_key_state = start_task(key, func, from, key_state)
      {:noreply, put_key_state(state, key, new_key_state)}
    else
      # No slot — queue the caller
      new_key_state = %{key_state | queue: key_state.queue ++ [{from, func}]}
      {:noreply, put_key_state(state, key, new_key_state)}
    end
  end

  def handle_call({:status, key}, _from, state) do
    key_state = Map.get(state.keys, key, empty_key_state())

    reply = %{
      running: key_state.running,
      queued: length(key_state.queue)
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info({:task_done, key, ref, result}, state) do
    case Map.fetch(state.keys, key) do
      {:ok, key_state} ->
        # Find the caller for this task and reply
        {from, new_tasks} = Map.pop(key_state.tasks, ref)

        if from do
          GenServer.reply(from, result)
        end

        new_key_state = %{key_state | running: key_state.running - 1, tasks: new_tasks}

        # Start the next queued caller if any
        new_key_state = maybe_start_next(key, new_key_state)

        # Clean up the key if completely idle
        if new_key_state.running == 0 and new_key_state.queue == [] do
          {:noreply, %{state | keys: Map.delete(state.keys, key)}}
        else
          {:noreply, put_key_state(state, key, new_key_state)}
        end

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

  defp empty_key_state do
    %{running: 0, queue: [], tasks: %{}}
  end

  defp put_key_state(state, key, key_state) do
    %{state | keys: Map.put(state.keys, key, key_state)}
  end

  defp start_task(key, func, from, key_state) do
    parent = self()
    ref = make_ref()

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

      send(parent, {:task_done, key, ref, result})
    end)

    %{
      key_state
      | running: key_state.running + 1,
        tasks: Map.put(key_state.tasks, ref, from)
    }
  end

  defp maybe_start_next(key, key_state) do
    case key_state.queue do
      [{from, func} | rest] ->
        new_key_state = %{key_state | queue: rest}
        start_task(key, func, from, new_key_state)

      [] ->
        key_state
    end
  end
end
```

## Failing test report

```
17 of 19 test(s) failed:

  * test executes the function and returns the result
      no function clause matching in KeyedPool.execute/3

  * test wraps plain return values in an ok tuple
      no function clause matching in KeyedPool.execute/3

  * test passes through {:error, reason} as-is
      no function clause matching in KeyedPool.execute/3

  * test exception is returned as {:error, {:exception, _}}
      no function clause matching in KeyedPool.execute/3

  (…13 more)
```
