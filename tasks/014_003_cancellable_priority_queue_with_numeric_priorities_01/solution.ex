defmodule CancellablePriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on numeric priority levels (lower = higher priority)
  with support for cancelling pending tasks by reference.
  """

  use GenServer

  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{processor: processor}, gen_opts)
  end

  @spec enqueue(server(), term(), non_neg_integer()) :: {:ok, reference()}
  def enqueue(server, task, priority) when is_integer(priority) and priority >= 0 do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @spec cancel(server(), reference()) :: :ok | {:error, :not_found}
  def cancel(server, ref) when is_reference(ref) do
    GenServer.call(server, {:cancel, ref})
  end

  @spec status(server()) :: %{
          pending: non_neg_integer(),
          by_priority: %{non_neg_integer() => non_neg_integer()},
          cancelled: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @spec peek(server()) :: {:ok, term(), non_neg_integer()} | :empty
  def peek(server) do
    GenServer.call(server, :peek)
  end

  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor}) do
    state = %{
      queues: %{},
      processor: processor,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      cancelled_count: 0,
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    ref = make_ref()
    entry = {ref, task}

    queue = Map.get(state.queues, priority, :queue.new())
    updated_queue = :queue.in(entry, queue)
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, {:ok, ref}, state}
  end

  def handle_call({:cancel, ref}, _from, state) do
    case find_and_remove(state.queues, ref) do
      {:found, updated_queues} ->
        queues = clean_empty_queues(updated_queues)
        state = %{state | queues: queues, cancelled_count: state.cancelled_count + 1}
        {:reply, :ok, state}

      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:status, _from, state) do
    by_priority =
      state.queues
      |> Enum.map(fn {priority, queue} -> {priority, :queue.len(queue)} end)
      |> Enum.filter(fn {_p, count} -> count > 0 end)
      |> Map.new()

    pending = Enum.reduce(by_priority, 0, fn {_p, count}, acc -> acc + count end)

    result = %{
      pending: pending,
      by_priority: by_priority,
      cancelled: state.cancelled_count
    }

    {:reply, result, state}
  end

  def handle_call(:peek, _from, state) do
    case peek_highest(state.queues) do
      nil ->
        {:reply, :empty, state}

      {task, priority} ->
        {:reply, {:ok, task, priority}, state}
    end
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

      {{_ref, task}, queues} ->
        queues = clean_empty_queues(queues)
        parent = self()
        processor = state.processor

        {pid, mon_ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | queues: queues,
            current_task: task,
            current_ref: {pid, mon_ref}
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:task_result, pid, result}, %{current_ref: {pid, _ref}} = state) do
    state = %{state | processed: [{state.current_task, result} | state.processed]}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, %{current_ref: {pid, ref}} = state) do
    state = %{state | current_task: nil, current_ref: nil}

    if queue_empty?(state) do
      state = %{state | processing: false} |> notify_drain_waiters()
      {:noreply, state}
    else
      send(self(), :process_next)
      {:noreply, state}
    end
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
    case sorted_priorities(queues) do
      [] ->
        {nil, queues}

      [priority | _rest] ->
        case :queue.out(queues[priority]) do
          {{:value, entry}, rest} ->
            {entry, Map.put(queues, priority, rest)}

          {:empty, _} ->
            {nil, queues}
        end
    end
  end

  defp peek_highest(queues) do
    case sorted_priorities(queues) do
      [] ->
        nil

      [priority | _rest] ->
        case :queue.peek(queues[priority]) do
          {:value, {_ref, task}} -> {task, priority}
          :empty -> nil
        end
    end
  end

  defp sorted_priorities(queues) do
    queues
    |> Map.keys()
    |> Enum.filter(fn p -> not :queue.is_empty(queues[p]) end)
    |> Enum.sort()
  end

  defp find_and_remove(queues, target_ref) do
    Enum.reduce_while(queues, :not_found, fn {priority, queue}, _acc ->
      items = :queue.to_list(queue)

      case Enum.split_with(items, fn {ref, _task} -> ref != target_ref end) do
        {remaining, [{^target_ref, _task}]} ->
          new_queue = :queue.from_list(remaining)
          updated_queues = Map.put(queues, priority, new_queue)
          {:halt, {:found, updated_queues}}

        {_all_items, []} ->
          {:cont, :not_found}
      end
    end)
  end

  defp clean_empty_queues(queues) do
    queues
    |> Enum.reject(fn {_priority, queue} -> :queue.is_empty(queue) end)
    |> Map.new()
  end

  defp queue_empty?(state) do
    Enum.all?(state.queues, fn {_p, queue} -> :queue.is_empty(queue) end)
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
