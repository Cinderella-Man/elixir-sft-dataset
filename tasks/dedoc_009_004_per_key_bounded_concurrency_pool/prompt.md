# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule KeyedPool do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    max_concurrency = Keyword.fetch!(opts, :max_concurrency)

    if not is_integer(max_concurrency) or max_concurrency < 1 do
      raise ArgumentError,
            ":max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
    end

    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{max_concurrency: max_concurrency}, server_opts)
  end

  def execute(server, key, func) when is_function(func, 0) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end

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
