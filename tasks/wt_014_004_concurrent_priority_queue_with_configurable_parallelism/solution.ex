defmodule ConcurrentPriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (:critical > :normal > :low)
  with configurable concurrency. Up to `:max_concurrency` tasks can be processed simultaneously.
  """

  use GenServer

  @type priority :: :critical | :normal | :low
  @type server :: GenServer.server()

  @priority_order [:critical, :normal, :low]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, 1)
    {name, _opts} = Keyword.pop(opts, :name)

    unless is_integer(max_concurrency) and max_concurrency > 0 do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, max_concurrency: max_concurrency},
      gen_opts
    )
  end

  @spec enqueue(server(), term(), priority()) :: :ok
  def enqueue(server, task, priority) when priority in @priority_order do
    GenServer.call(server, {:enqueue, task, priority})
  end

  @spec status(server()) :: %{
          critical: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer(),
          active: non_neg_integer(),
          max_concurrency: pos_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
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
  def init(%{processor: processor, max_concurrency: max_concurrency}) do
    state = %{
      queues: %{critical: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      max_concurrency: max_concurrency,
      # Map of pid => {task, monitor_ref}
      active_workers: %{},
      # Map of pid => result (received before :DOWN)
      pending_results: %{},
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
      critical: :queue.len(state.queues.critical),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low),
      active: map_size(state.active_workers),
      max_concurrency: state.max_concurrency
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    if map_size(state.active_workers) >= state.max_concurrency do
      # All slots full, do nothing — will be re-triggered when a worker finishes
      {:noreply, state}
    else
      case pop_highest(state.queues) do
        {nil, _queues} ->
          # Nothing to process
          state = maybe_notify_drain(state)
          {:noreply, state}

        {task, queues} ->
          parent = self()
          processor = state.processor

          {pid, ref} =
            spawn_monitor(fn ->
              result = processor.(task)
              send(parent, {:task_result, self(), result})
            end)

          active_workers = Map.put(state.active_workers, pid, {task, ref})

          new_state = %{state | queues: queues, active_workers: active_workers}

          # Try to fill more slots if available
          new_state = maybe_trigger_processing(new_state)

          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_result, pid, result}, state) do
    if Map.has_key?(state.active_workers, pid) do
      # Store result, will be finalized on :DOWN
      state = %{state | pending_results: Map.put(state.pending_results, pid, result)}
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.active_workers, pid) do
      {{task, ^ref}, remaining_workers} ->
        # Finalize the result
        {result, pending_results} = Map.pop(state.pending_results, pid)

        processed =
          if result != nil do
            [{task, result} | state.processed]
          else
            state.processed
          end

        state = %{
          state
          | active_workers: remaining_workers,
            pending_results: pending_results,
            processed: processed
        }

        # Try to start more work
        state = maybe_trigger_processing(state)
        state = maybe_notify_drain(state)

        {:noreply, state}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp maybe_trigger_processing(state) do
    available_slots = state.max_concurrency - map_size(state.active_workers)

    if available_slots > 0 and not queue_empty?(state) do
      send(self(), :process_next)
    end

    state
  end

  defp pop_highest(queues) do
    Enum.find_value(@priority_order, {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, task}, rest} -> {task, Map.put(queues, priority, rest)}
        {:empty, _} -> nil
      end
    end)
  end

  defp queue_empty?(state) do
    Enum.all?(@priority_order, fn p -> :queue.is_empty(state.queues[p]) end)
  end

  defp maybe_notify_drain(state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      notify_drain_waiters(state)
    else
      state
    end
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
