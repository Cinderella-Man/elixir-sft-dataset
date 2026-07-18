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
defmodule PriorityQueue do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{processor: processor}, gen_opts)
  end

  def enqueue(server, task, priority) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority})
  end

  def status(server) do
    GenServer.call(server, :status)
  end

  def processed(server) do
    GenServer.call(server, :processed)
  end

  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor}) do
    state = %{
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    updated_queue = :queue.in(task, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    counts = %{
      high: :queue.len(state.queues.high),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low)
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and not state.processing do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    case pop_highest(state.queues) do
      {nil, _queues} ->
        state = %{state | processing: false} |> notify_drain_waiters()
        {:noreply, state}

      {task, queues} ->
        parent = self()
        processor = state.processor

        {pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | queues: queues,
            current_task: task,
            current_ref: {pid, ref}
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:task_result, pid, result}, %{current_ref: {pid, _ref}} = state) do
    state = %{state | processed: [{state.current_task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %{current_ref: {pid, ref}} = state) do
    state = %{state | current_task: nil, current_ref: nil}
    send(self(), :process_next)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp maybe_trigger_processing(%{processing: true} = state), do: state

  defp maybe_trigger_processing(state) do
    if queue_empty?(state) do
      state
    else
      send(self(), :process_next)
      %{state | processing: true}
    end
  end

  defp pop_highest(queues) do
    Enum.find_value([:high, :normal, :low], {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, task}, rest} -> {task, Map.put(queues, priority, rest)}
        {:empty, _} -> nil
      end
    end)
  end

  defp queue_empty?(state) do
    Enum.all?([:high, :normal, :low], fn p -> :queue.is_empty(state.queues[p]) end)
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
```
