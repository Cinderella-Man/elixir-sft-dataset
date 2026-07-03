Implement the `handle_info/2` GenServer callback(s).

`handle_info/2` handles the internal `{:task_done, key, ref, result}` message that a
spawned worker `Task` sends back (via `send/2`) once its function has finished running.
It must:

1. Look up the per-key state for `key` in `state.keys`. If the key is not present
   (`:error`), there is nothing to do — return `{:noreply, state}` unchanged.
2. When the key state exists, pop the task reference `ref` out of that key's `tasks`
   map to find the `from` of the caller who owns this task. If a `from` was found,
   reply to that caller with `result` using `GenServer.reply/2` (this is what unblocks
   the original `execute/3` caller).
3. Decrement the key's `running` count by 1 and store the updated `tasks` map (with
   `ref` removed).
4. Since a slot just freed up, start the next queued caller's function, if any, using
   `maybe_start_next/2`.
5. Clean up bookkeeping: if the resulting key state is completely idle
   (`running == 0` and its `queue` is empty), delete the key from `state.keys`
   entirely; otherwise store the updated key state back with `put_key_state/3`.
   Either way return `{:noreply, new_state}`.

Also provide the catch-all clause: any other message must be ignored, returning
`{:noreply, state}` unchanged.

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
      raise ArgumentError, ":max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
    end

    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{max_concurrency: max_concurrency}, server_opts)
  end

  @spec execute(GenServer.server(), term(), (() -> term())) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func) when is_function(func, 0) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end

  @spec status(GenServer.server(), term()) :: %{running: non_neg_integer(), queued: non_neg_integer()}
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
    # TODO
  end

  def handle_info(_msg, state) do
    # TODO
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