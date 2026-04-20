defmodule ExpiringPriorityQueue do
  @moduledoc """
  A GenServer that processes tasks based on priority levels (:high > :normal > :low),
  with per-task TTL support. Tasks that expire before being picked up are skipped
  and recorded in an expired list.
  """

  use GenServer

  @type priority :: :high | :normal | :low
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {default_ttl_ms, opts} = Keyword.pop(opts, :default_ttl_ms, 5000)
    {clock, opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {name, _opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock},
      gen_opts
    )
  end

  @spec enqueue(server(), term(), priority(), keyword()) :: :ok
  def enqueue(server, task, priority, opts \\ []) when priority in [:high, :normal, :low] do
    GenServer.call(server, {:enqueue, task, priority, opts})
  end

  @spec status(server()) :: %{
          high: non_neg_integer(),
          normal: non_neg_integer(),
          low: non_neg_integer(),
          expired: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end

  @spec expired(server()) :: [{term(), priority()}]
  def expired(server) do
    GenServer.call(server, :expired)
  end

  @spec drain(server()) :: :ok
  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor, default_ttl_ms: default_ttl_ms, clock: clock}) do
    state = %{
      queues: %{high: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      default_ttl_ms: default_ttl_ms,
      clock: clock,
      processing: false,
      current_task: nil,
      current_ref: nil,
      processed: [],
      expired: [],
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority, opts}, _from, state) do
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
    now = state.clock.()
    expires_at = now + ttl_ms

    entry = {task, expires_at}
    updated_queue = :queue.in(entry, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    now = state.clock.()

    counts =
      Enum.reduce([:high, :normal, :low], %{}, fn priority, acc ->
        count =
          state.queues[priority]
          |> :queue.to_list()
          |> Enum.count(fn {_task, expires_at} -> expires_at > now end)

        Map.put(acc, priority, count)
      end)

    counts = Map.put(counts, :expired, length(state.expired))

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:expired, _from, state) do
    {:reply, Enum.reverse(state.expired), state}
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
    case pop_next_valid(state) do
      {:empty, state} ->
        state = %{state | processing: false} |> notify_drain_waiters()
        {:noreply, state}

      {:ok, task, state} ->
        parent = self()
        processor = state.processor

        {pid, ref} =
          spawn_monitor(fn ->
            result = processor.(task)
            send(parent, {:task_result, self(), result})
          end)

        new_state = %{
          state
          | current_task: task,
            current_ref: {pid, ref}
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

  # Pops entries from the queues in priority order, skipping expired ones.
  # Returns {:ok, task, updated_state} or {:empty, updated_state}.
  defp pop_next_valid(state) do
    case pop_highest(state.queues) do
      {nil, _queues} ->
        {:empty, state}

      {{task, expires_at}, queues, priority} ->
        now = state.clock.()
        state = %{state | queues: queues}

        if expires_at <= now do
          # Task has expired — record it and try the next one
          state = %{state | expired: [{task, priority} | state.expired]}
          pop_next_valid(state)
        else
          {:ok, task, state}
        end
    end
  end

  defp pop_highest(queues) do
    Enum.find_value([:high, :normal, :low], {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, entry}, rest} -> {entry, Map.put(queues, priority, rest), priority}
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
